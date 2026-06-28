import yfinance as yf
import json
import datetime
import os
import sys
from decimal import Decimal, ROUND_HALF_UP
import concurrent.futures # ★追加: マルチスレッド用

THRESHOLD = 90

# ヘルパー関数: 正確な四捨五入を行う（RSIスクリプトより流用）
def round_half_up(number, decimals=1):
    """
    数値を指定した桁数で四捨五入(ROUND_HALF_UP)してfloatで返す
    Noneの場合はNoneを返す
    """
    if number is None:
        return None
    try:
        d = Decimal(str(number))
        exp = Decimal("1." + "0" * decimals)
        return float(d.quantize(exp, rounding=ROUND_HALF_UP))
    except:
        return None

def load_mst():
    if not os.path.exists("tickers.json"):
        sys.stderr.write("ERROR: tickers.json not found.\n")
        return {}
    with open("tickers.json", "r", encoding="utf-8") as f:
        return json.load(f)

def load_result(date):
    result_file = f"./result/{date}.json"
    if os.path.exists(result_file):
        with open(result_file, "r", encoding="utf-8") as f:
            return json.load(f).get("result", {})
    return {}

def get_stock_data(symbol):
    try:
        stock = yf.Ticker(symbol)
        # auto_adjust=Falseに変更し、配当落ち調整なしの株価を取得
        hist = stock.history(period="6mo", interval="1d", auto_adjust=False)
        
        if hist.empty:
            return "0", [], []

        # NaNを含む行を削除（Close列基準）
        clean_hist = hist[["Close"]].dropna()
        prices = clean_hist["Close"].tolist()
        
        # 日付リストを作成 (YYYY-MM-DD)
        dates = [d.strftime('%Y-%m-%d') for d in clean_hist.index]
        
        last_end_date = clean_hist.index[-1].strftime("%Y-%m-%dT%H:%M:%S") if len(clean_hist) > 0 else "0"
        
        return last_end_date, prices, dates
    except Exception as e:
        sys.stderr.write(f"ERROR: {symbol} - {e}\n")
        return "0", [], []

def moving_average(prices, days):
    if len(prices) < days:
        return [None] * len(prices)
    return [None] * (days - 1) + [sum(prices[i - days + 1:i + 1]) / days for i in range(days - 1, len(prices))]

def detect_cross(prices, ma25, ma75, threshold):
    # 配列末尾の要素が存在しない(None)場合は計算不可
    if len(prices) < 2 or ma25[-1] is None or ma75[-1] is None:
        return {"golden_cross": 0, "dead_cross": 0, "golden_cross_near": 0, "dead_cross_near": 0}
    
    # 1つ前のデータもNoneチェック
    if ma25[-2] is None or ma75[-2] is None:
        return {"golden_cross": 0, "dead_cross": 0, "golden_cross_near": 0, "dead_cross_near": 0}

    result = {"golden_cross": 0, "dead_cross": 0, "golden_cross_near": 0, "dead_cross_near": 0}
    
    # ゴールデンクロス / デッドクロス判定
    if ma25[-2] < ma75[-2] and ma25[-1] > ma75[-1]:
        result["golden_cross"] = 1
    elif ma25[-2] > ma75[-2] and ma25[-1] < ma75[-1]:
        result["dead_cross"] = 1
    
    # 接近判定
    price_ma_diff = abs(prices[-1] - ma75[-1])
    if price_ma_diff <= threshold:
        proximity = 100 * (1 - price_ma_diff / threshold)
        if prices[-1] > ma75[-1]:
            result["golden_cross_near"] = proximity
        elif prices[-1] < ma75[-1]:
            result["dead_cross_near"] = proximity
            
    return result

# ★追加: 1銘柄分の処理を独立した関数に切り出し
def process_single_ticker(ticker, info, mode, threshold):
    # 対象市場のフィルタリング
    if mode == "P" and "プライム" in info["class"]:
        pass
    elif mode == "S" and "スタンダード" in info["class"]:
        pass
    elif mode == "G" and "グロース" in info["class"]:
        pass
    else:
        return None # 対象外

    symbol = f"{ticker}.T"
    last_end_date, prices, dates = get_stock_data(symbol)
    
    # データ不足チェック (75日平均を出すため75日分必要)
    if len(prices) < 75:
        sys.stderr.write(f"  - prices is short ({len(prices)} < 75). Skipping {symbol}.\n")
        return None
        
    ma25 = moving_average(prices, 25)
    ma75 = moving_average(prices, 75)
    
    cross_result = detect_cross(prices, ma25, ma75, threshold)
    
    history_data = []
    data_len = len(dates)
    start_idx = max(0, data_len - 60)
    
    for i in range(start_idx, data_len):
        history_data.append({
            "d": dates[i],
            "p": round_half_up(prices[i], 1),
            "m25": round_half_up(ma25[i], 2),
            "m75": round_half_up(ma75[i], 2)
        })
        
    return ticker, {
        **cross_result, 
        "price": prices[-1], 
        "end_date": last_end_date,
        "history": history_data
    }

def main(mode="P"):
    today = datetime.datetime.utcnow().strftime('%Y%m%d')
    tickers = load_mst()
    result = load_result(today)
    
    # 処理対象の銘柄だけをリストアップ
    target_items = [
        (t, info) for t, info in tickers.items()
        if (mode == "P" and "プライム" in info["class"]) or
           (mode == "S" and "スタンダード" in info["class"]) or
           (mode == "G" and "グロース" in info["class"])
    ]
    total = len(target_items)
    count = 0

    # ★変更: ThreadPoolExecutorで並行処理を実行する
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        # 順番を維持しつつ並行でデータ取得と計算を行う
        results = executor.map(lambda item: process_single_ticker(item[0], item[1], mode, THRESHOLD), target_items)
        
        for res in results:
            count += 1
            if res is not None:
                t, data = res
                result[t] = data
                sys.stderr.write(f"{count}/{total} t:{t} completed\n")
            else:
                sys.stderr.write(f"{count}/{total} skipped\n")
            
    now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')
    output = {"date_modified": now, "result": result}
    sys.stdout.write(json.dumps(output, ensure_ascii=False, separators=(',', ':')) + "\n")

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "P"
    main(mode)
