#!/usr/bin/perl
use strict;
use warnings;

use LWP::UserAgent;
use JSON;

my $api_key = 'YOUR_ALPHA_VANTAGE_API_KEY';
my $symbol = '7011.T';
my $output_file = 'cross_results.json';


# 株価データの取得
sub get_stock_data {
    my ($symbol, $api_key) = @_;
    my $ua = LWP::UserAgent->new;
    my $url = "https://query2.finance.yahoo.com/v8/finance/chart/7011.T";
    #my $url = "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=$symbol&apikey=$api_key";
    #my $response = $ua->get($url);
    my $response = `curl $url`;

    #die "Failed to get data: ", $response->status_line unless $response->is_success;

    #my $data = decode_json($response->decoded_content);
    print STDERR "ret:$response";
    my $data = decode_json($response);
    my $currency = $data->{chart}{result}[0]{meta}{currency};
    my $symb = $data->{chart}{result}[0]{meta}{symbol};
    
    my @prices = ($currency, $symb);
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
    my ($prices, $ma) = @_;
    my %result = (golden_cross => 0, dead_cross => 0);
    for my $i (1..$#$prices) {
        if (defined $ma->[$i] && defined $ma->[$i-1]) {
            if ($prices->[$i] > $ma->[$i] && $prices->[$i-1] <= $ma->[$i-1]) {
                $result{golden_cross} = 1;
            } elsif ($prices->[$i] < $ma->[$i] && $prices->[$i-1] >= $ma->[$i-1]) {
                $result{dead_cross} = 1;
            }
        }
    }
    return %result;
}

# メインルーチン
sub main {
    my @prices = get_stock_data($symbol, $api_key);
    #my @ma75 = moving_average(\@prices, 75);
    #my %result = detect_cross(\@prices, \@ma75);
    my %result = ($prices[0] => $prices[1]);

    #open my $fh, '>', $output_file or die "Could not open file '$output_file': $!";
    #print $fh encode_json(\%result);
    #close $fh;

    print encode_json(\%result);
}

main();
