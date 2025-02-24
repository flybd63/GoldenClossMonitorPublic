import yfinance as yf
import json
import datetime
import os

THRESHOLD = 90
def load_mst():
    with open("tickers.json", "r", encoding="utf-8") as f:
        return json.load(f)

def load_result(date):
    result_file = f"./result/{date}.json"
    if os.path.exists(result_file):
        with open(result_file, "r", encoding="utf-8") as f:
            return json.load(f).get("result", {})
    return {}

def save_json(ticker, data):
    output_path = f"./result/{ticker}.json"
    tmpfile = output_path + "tmp"
    with open(tmpfile, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    os.rename(tmpfile, output_path)

def get_stock_data(symbol):
    try:
        stock = yf.Ticker(symbol)
        hist = stock.history(period="6mo", interval="1d")
        prices = hist["Close"].dropna().tolist()
        last_end_date = hist.index[-1].strftime("%Y-%m-%dT%H:%M:%S") if len(hist) > 0 else "0"
        return last_end_date, prices
    except Exception as e:
        print(f"ERROR: {symbol} - {e}")
        return "0", []

def moving_average(prices, days):
    if len(prices) < days:
        return [None] * len(prices)
    return [None] * (days - 1) + [sum(prices[i - days + 1:i + 1]) / days for i in range(days - 1, len(prices))]

def detect_cross(prices, ma25, ma75, threshold):
    if len(prices) < 2 or not ma25[-1] or not ma75[-1]:
        return {"golden_cross": 0, "dead_cross": 0, "golden_cross_near": 0, "dead_cross_near": 0}
    result = {"golden_cross": 0, "dead_cross": 0, "golden_cross_near": 0, "dead_cross_near": 0}
    if ma25[-2] < ma75[-2] and ma25[-1] > ma75[-1]:
        result["golden_cross"] = 1
    elif ma25[-2] > ma75[-2] and ma25[-1] < ma75[-1]:
        result["dead_cross"] = 1
    price_ma_diff = abs(prices[-1] - ma75[-1])
    if price_ma_diff <= threshold:
        proximity = 100 * (1 - price_ma_diff / threshold)
        if prices[-1] > ma75[-1]:
            result["golden_cross_near"] = proximity
        elif prices[-1] < ma75[-1]:
            result["dead_cross_near"] = proximity
    return result

def main(mode="P"):
    today = datetime.datetime.utcnow().strftime('%Y%m%d')
    tickers = load_mst()
    result = load_result(today)
    
    for count, (ticker, info) in enumerate(tickers.items(), 1):
        if mode not in info["class"]:
            continue
        print(f"{count}/{len(tickers)} t:{ticker} {info['name']} {info['class']}")
        symbol = f"{ticker}.T"
        last_end_date, prices = get_stock_data(symbol)
        if len(prices) < 75 or any(p is None for p in prices):
            print("  - prices is short or has null values. Skipping.")
            continue
        ma25, ma75 = moving_average(prices, 25), moving_average(prices, 75)
        cross_result = detect_cross(prices, ma25, ma75, THRESHOLD)
        if any(cross_result.values()):
            result[ticker] = {**cross_result, "price": prices[-1], "end_date": last_end_date}
    
    now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')
    output = {"date_modified": now, "result": result}
    print(json.dumps(output, indent=4, ensure_ascii=False))
    save_json("latest", output)

if __name__ == "__main__":
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "P"
    main(mode)
