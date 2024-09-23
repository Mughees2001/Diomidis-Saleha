#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

# Include necessary modules
use Digest::MD5 qw(md5_hex);

# Copy the line_details function from your script
sub line_details {
    my ($l) = @_;

    my $len = length($l);

    my $string = 0;
    while ($l =~ s/\"[^"]*\"//) {
        $string++;
    }
    while ($l =~ s/\'[^']*\'//) {
        $string++;
    }

    my $comment = (($l =~ s/\/\*.*//) || ($l =~ s/\#.*//) || ($l =~ s/\/\/.*//)) + 0;

    while ($l =~ s/\t+/' ' x (length($&) * 8 - length($`) % 8)/e) {
    }
    $l =~ /^( *)/g;
    my $startspace = length($1);

    my $comma = () = $l =~ /\,/g;
    my $bracket = () = $l =~ /\(/g;
    my $access = () = $l =~ /\.[^0-9]|\-\>/g;
    my $assignment = () = $l =~ /[^<>!~=]\=[^=]|\<\<\=|\>\>\=/g;
    my $scope = () = $l =~ /\{|(:\s*$)/g;
    my $array = () = $l =~ /\[/g;
    my $logical = () = $l =~ /\=\=|[^>]\>\=|[^<]\<\=|\!\=|[^<]\<[^<]|[^->]\>[^>]|\!|\|\||\&\&|\bor\b|\band\b|\bnot\b|\bis\b/g;
    return "$len $startspace $string $comment $comma $bracket $access $assignment $scope $array $logical";
}

# Test cases
my @test_cases = (
    { input => 'xx', expected => '2 0 0 0 0 0 0 0 0 0 0' },
    { input => "'x'", expected => '3 0 1 0 0 0 0 0 0 0 0' },
    { input => '#x(', expected => '3 0 0 1 0 0 0 0 0 0 0' },
    { input => '/*(', expected => '3 0 0 1 0 0 0 0 0 0 0' },
    { input => '//(', expected => '3 0 0 1 0 0 0 0 0 0 0' },
    { input => 'a,b,c', expected => '5 0 0 0 2 0 0 0 0 0 0' },
    { input => '((', expected => '2 0 0 0 0 2 0 0 0 0 0' },
    { input => 'a.b', expected => '3 0 0 0 0 0 1 0 0 0 0' },
    { input => 'a->b', expected => '4 0 0 0 0 0 1 0 0 0 0' },
    { input => '1.2', expected => '3 0 0 0 0 0 0 0 0 0 0' },
    { input => 'a=b', expected => '3 0 0 0 0 0 0 1 0 0 0' },
    { input => 'a<<=b', expected => '5 0 0 0 0 0 0 1 0 0 0' },
    { input => 'a*=b', expected => '4 0 0 0 0 0 0 1 0 0 0' },
    { input => '{', expected => '1 0 0 0 0 0 0 0 1 0 0' },
    { input => ': ', expected => '2 0 0 0 0 0 0 0 1 0 0' },
    { input => 'x:', expected => '2 0 0 0 0 0 0 0 1 0 0' },
    { input => '[', expected => '1 0 0 0 0 0 0 0 0 1 0' },
    { input => '==', expected => '2 0 0 0 0 0 0 0 0 0 1' },
    { input => 'a>=', expected => '3 0 0 0 0 0 0 0 0 0 1' },
    { input => 'b<=', expected => '3 0 0 0 0 0 0 0 0 0 1' },
    { input => '!=', expected => '2 0 0 0 0 0 0 0 0 0 1' },
    { input => 'a<b', expected => '3 0 0 0 0 0 0 0 0 0 1' },
    { input => 'a<<b', expected => '4 0 0 0 0 0 0 0 0 0 0' },
    { input => 'a>b', expected => '3 0 0 0 0 0 0 0 0 0 1' },
    { input => '!!', expected => '2 0 0 0 0 0 0 0 0 0 2' },
    { input => '||', expected => '2 0 0 0 0 0 0 0 0 0 1' },
    { input => '&&', expected => '2 0 0 0 0 0 0 0 0 0 1' },
    { input => 'a and b', expected => '7 0 0 0 0 0 0 0 0 0 1' },
    { input => 'a or b', expected => '6 0 0 0 0 0 0 0 0 0 1' },
    { input => 'not b', expected => '5 0 0 0 0 0 0 0 0 0 1' },
    { input => 'notb', expected => '4 0 0 0 0 0 0 0 0 0 0' },
    { input => 'is not', expected => '6 0 0 0 0 0 0 0 0 0 2' },
    { input => ' x', expected => '2 1 0 0 0 0 0 0 0 0 0' },
    { input => '   x', expected => '4 3 0 0 0 0 0 0 0 0 0' },
    { input => "\t", expected => '1 8 0 0 0 0 0 0 0 0 0' },
    { input => "\t\tx", expected => '3 16 0 0 0 0 0 0 0 0 0' },
);

# Run tests
foreach my $case (@test_cases) {
    my $result = line_details($case->{input});
    is($result, $case->{expected}, "line_details('$case->{input}')");
}

done_testing();
