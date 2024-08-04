#!/usr/bin/perl
use strict;
use warnings;

use JSON;
use Time::Piece;


my $threshold = 90;
my $today = localtime->strftime('%Y%m%d');

# メインルーチン
my %tikers = %{&load_mst()};
my $len = scalar(keys %tikers);
my $count = 1;
my %result = ();
foreach my $t (sort keys %tikers){
    print STDERR "$count/$len t:$t\n";
    my $symbol = "$t.T";

    my @prices = get_stock_data($symbol);
    my @ma75 = moving_average(\@prices, 75);
    my %r = detect_cross(\@prices, \@ma75, $threshold);
    
    if($r{golden_cross} == 1 || $r{dead_cross} == 1 || $r{golden_cross_near} == 1 || $r{dead_cross_near} == 1){
        $result{$t} = ();
        $result{$t}{golden_cross} = $r{golden_cross};
        $result{$t}{dead_cross} = $r{dead_cross};
        $result{$t}{golden_cross_near} = $r{golden_cross_near};
        $result{$t}{dead_cross_near} = $r{dead_cross_near};
    }

    $count ++;
    #last;
}

print encode_json(\%result);

#&save_json($today, encode_json(\%result));
#&save_json("latest", encode_json(\%result));


#My %result = ($prices[0] => $prices[1]);

#open my $fh, '>', $output_file or die "Could not open file '$output_file': $!";
#print $fh encode_json(\%result);
#close $fh;
#print encode_json(\%result);

exit 0;


################################################################################
### SubRoutines ################################################################
################################################################################

sub load_mst {
    my $tikers_file = "./tikers.json";
    
    open(IN, $tikers_file);
    my $mst_jtxt = <IN>;
    close IN;
    my $mst_json = from_json($mst_jtxt);
    
    return $mst_json;
}

sub save_json {
    my ($ticker, $json) = @_;

    my $out = "./result/$ticker.json";
    my $tmpfile = $out."tmp";

    open( OUT, "> $tmpfile" ) or die $!;
    print OUT $json;
    close OUT;
    rename($tmpfile, $out);
    
}

# 株価データの取得
sub get_stock_data {
    my ($symbol) = @_;
    
    my $url = '"https://query2.finance.yahoo.com/v8/finance/chart/7011.T?range=6mo&interval=1d"';
    #my $url = "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=$symbol&apikey=$api_key";
    #my $response = $ua->get($url);
    my $response = `curl -sS $url`;

    #die "Failed to get data: ", $response->status_line unless $response->is_success;

    #my $data = decode_json($response->decoded_content);
    #print STDERR "ret:$response";
    my $data = decode_json($response);
    my @prices = reverse( @{$data->{chart}{result}[0]{indicators}{quote}[0]{close}} );
    splice(@prices, 75);
    
    
#    foreach my $date (sort keys %$time_series) {
#        push @prices, $time_series->{$date}->{'4. close'};
#    }
    return @prices;
}

# 移動平均の計算
sub moving_average {
    my ($prices, $days) = @_;
    my @ma;
    for my $i (0..$#$prices) {
        if ($i >= $days - 1) {
            my $sum = 0;
            $sum += $prices->[$_] for ($i - $days + 1..$i);
            push @ma, $sum / $days;
        } else {
            push @ma, undef;
        }
    }
    return @ma;
}

# ゴールデンクロス・デッドクロスの検出
sub detect_cross {
    my ($prices, $ma, $threshold) = @_;
    my %result = (golden_cross => 0, dead_cross => 0, golden_cross_near => 0, dead_cross_near => 0);
    my $total_price = @$prices;
    for my $i (1..$#$prices) {
        if (defined $ma->[$i] && defined $ma->[$i-1]) {
            my $price_ma_diff = abs($prices->[$i] - $ma->[$i]);
            if ($prices->[$i] > $ma->[$i] && $prices->[$i-1] <= $ma->[$i-1]) {
                $result{golden_cross} = 1;
            } elsif ($prices->[$i] < $ma->[$i] && $prices->[$i-1] >= $ma->[$i-1]) {
                $result{dead_cross} = 1;
            }
            if ($price_ma_diff <= $threshold) {
                my $proximity = 100 * (1 - $price_ma_diff / $threshold);
                if ($prices->[$i] > $ma->[$i]) {
                    $result{golden_cross_near} = $proximity;
                } elsif ($prices->[$i] < $ma->[$i]) {
                    $result{dead_cross_near} = $proximity;
                }
            }
        }
    }
    return %result;
}

