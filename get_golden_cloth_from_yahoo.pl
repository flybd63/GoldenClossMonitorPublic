#!/usr/bin/perl
use strict;
use warnings;

use JSON;
use Time::Piece;
use DateTime;
use POSIX qw(strftime);

my $threshold = 90;
my $today = localtime->strftime('%Y%m%d');

my $mode = $ARGV[0];#P,S,G(プライム、スタンダード、グロース)
if( ! defined $mode || $mode eq ''){ $mode = "P"; };#指定なければプライムだけ

# メインルーチン
my %tikers = %{&load_mst()};
my $len = scalar(keys %tikers);
my $count = 0;
my %result = %{&load_result($today)};

foreach my $t (sort keys %tikers){
    $count++;

    #if($t ne "1941"){ next; }

    if( $mode =~ "P" && $tikers{$t}{class} =~ /^プライム/ ){}
    elsif( $mode =~ "S" && $tikers{$t}{class} =~ /^スタンダード/){}
    elsif( $mode =~ "G" && $tikers{$t}{class} =~ /^グロース/ ){}
    else{ next; }

    print STDERR "$count/$len t:$t $tikers{$t}{name} $tikers{$t}{class}\n";
    my $symbol = "$t.T";
    
    my ($last_end_date, @prices) = get_stock_data($symbol);

    if($#prices < 74){
        print STDERR "  - prices is short. skip. len: $#prices\n";
        next;
    }

    if (grep { !defined($_) } @prices) {
        print STDERR "princes has null. skip\n";
        next;
    }
    
    my @ma25 = moving_average(\@prices, 25);
    my @ma75 = moving_average(\@prices, 75);

    my %r = detect_cross(\@prices, \@ma25, \@ma75, $threshold);
    
    if($r{golden_cross} == 1 || $r{dead_cross} == 1 || $r{golden_cross_near} == 1 || $r{dead_cross_near} == 1){
        $result{$t} = ();
        $result{$t}{golden_cross} = $r{golden_cross};
        $result{$t}{dead_cross} = $r{dead_cross};
        $result{$t}{golden_cross_near} = $r{golden_cross_near};
        $result{$t}{dead_cross_near} = $r{dead_cross_near};
        $result{$t}{price} = $prices[-1];
        $result{$t}{end_date} = strftime("%Y-%m-%dT%H:%M:%S", gmtime($last_end_date));
    }

    #last
}

my $now = DateTime->now(time_zone => 'GMT');
my $formatted_date = $now->strftime('%Y-%m-%dT%H:%M:%S');

my %out = (
    date_modified => $formatted_date,
    result => \%result
    );

print encode_json(\%out);

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
    my $tikers_file = "./tickers.json";
    
    open(IN, $tikers_file);
    my $mst_jtxt = <IN>;
    close IN;
    my $mst_json = from_json($mst_jtxt);
    
    return $mst_json;
}

sub load_result {
    my ($date) = @_;
    my $result_file = "./result/$date.json";

    my $json = {};
    $json->{result} = {};
    
    if(-e $result_file){
        open(IN, $result_file);
        my $jtxt = <IN>;
        close IN;
        $json = from_json($jtxt);
    }        
    return $json->{result};
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

    my $end_date = '0';
    my @prices = ();

    eval{
        my $url = '"https://query2.finance.yahoo.com/v8/finance/chart/'.$symbol.'?range=6mo&interval=1d"';
        
        #my $url = "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=$symbol&apikey=$api_key";
        #my $response = $ua->get($url);
        my $response = `curl -sS $url`;

        #die "Failed to get data: ", $response->status_line unless $response->is_success;

        #my $data = decode_json($response->decoded_content);
        #print STDERR "ret:$response";
        my $data = decode_json($response);
        #my @prices = reverse( @{$data->{chart}{result}[0]{indicators}{quote}[0]{close}} );
        #splice(@prices, 76);

        @prices = @{$data->{chart}{result}[0]{indicators}{quote}[0]{close}};

        $end_date = $data->{chart}{result}[0]{meta}{currentTradingPeriod}{regular}{end};
        
        #    foreach my $date (sort keys %$time_series) {
        #        push @prices, $time_series->{$date}->{'4. close'};
        #    }
    };
    if($@){
        print STDERR "ERROR:symbol: $symbol\n$@";
    }
    return ($end_date, @prices);
}

# 移動平均の計算
sub moving_average {
    my ($prices, $days) = @_;
    my @ma;
    for my $i (0..$#$prices) {
        if ($i >= $days - 1) {
            my $sum = 0;
            for (my $j = $i - $days + 1; $j <= $i; $j++) {
                my $p = 0;
                if(defined $prices->[$j]){
                    $p = $prices->[$j];
                }
                $sum += $p;
            }
                #$sum += $prices->[$_] for ($i - $days + 1..$i);
            push @ma, $sum / $days;
        } else {
            push @ma, undef;
        }
    }

    #print STDERR "ma$days: @ma\n";
    return @ma;
}

# ゴールデンクロス・デッドクロスの検出
sub detect_cross {
    my ($prices, $ma25, $ma75, $threshold) = @_;
    my %result = (golden_cross => 0, dead_cross => 0, golden_cross_near => 0, dead_cross_near => 0);
    my $total_price = @$prices;
    my $i = $#$prices;
    #for my $i (1..$#$prices) {
    #next unless defined $ma25->[$i] && defined $ma75->[$i];

    my $price_ma_diff = abs($prices->[$i] - $ma75->[$i]);

    if ($ma25->[$i - 1] < $ma75->[$i - 1] && $ma25->[$i] > $ma75->[$i]) {
        $result{golden_cross} = 1;
    } elsif ($ma25->[$i - 1] > $ma75->[$i - 1] && $ma25->[$i] < $ma75->[$i]) {
        $result{dead_cross} = 1;
    }
    if ($price_ma_diff <= $threshold) {
        my $proximity = 100 * (1 - $price_ma_diff / $threshold);
        if ($prices->[$i] > $ma75->[$i]) {
            $result{golden_cross_near} = $proximity;
        } elsif ($prices->[$i] < $ma75->[$i]) {
            $result{dead_cross_near} = $proximity;
        }
    }

    #}
    return %result;
}

