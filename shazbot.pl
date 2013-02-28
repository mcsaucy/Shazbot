#!/usr/bin/perl
#shazbot.pl
#Author: Josh McSavaney with heavily modified example code from various locations
#Usage: perl shazbot.pl #channel

use strict;
use warnings;
use HTML::Entities;
use URI::Escape;

# We will use a raw socket to connect to the IRC server.
use IO::Socket::SSL;

sub shorten($);
sub wiki($);
sub wolfram($);

# The server to connect to and our details.
my $server = "irc.csh.rit.edu";
my $nick = "ShazBot";
my $login = "SauceBot";

my $channel = "#freshmen";
# The channel which the bot will join.
if ($#ARGV < 0)
{
	$channel = "#freshmen";
}
else
{
	$channel = "#".shift;
}

# Connect to the IRC server.
my $sock = new IO::Socket::SSL(PeerAddr => $server,
                                PeerPort => 6697,
                                Proto => 'tcp',
								SSL_verify_mode => SSL_VERIFY_NONE ) or
                                    die "Can't connect\n";
print "Connected\n";
# Log on to the server.
print $sock "NICK $nick\r\n";
print $sock "USER $login 8 * :Prototype IRC bot\r\n";
print "So far so good...\n";
# Read lines from the server until it tells us we have connected.
while (my $input = <$sock>) {
    # Check the numerical responses from the server.
    if ($input =~ /004/) {
        # We are now logged in.
        last;
    }
    elsif ($input =~ /433/) {
        die "Nickname is already in use.";
    }
	elsif ($input =~ /^PING(.*)$/i) {
		print $sock "PONG $1\r\n";
	}
}

# Join the channel.
print $sock "JOIN $channel\r\n";

my $chan = $channel;

# Keep reading lines from the server.
while (my $input = <$sock>) {
    chomp $input;
	chop $input;
	my ($chan) = $input =~ m/PRIVMSG (#?[^\s]+) :/i;
	$chan = "" if not defined $chan;
	my $out = $chan;
	
	if ($input =~ /^PING(.*)$/i) {
        print $sock "PONG $1\r\n";
    }
	elsif ($input =~ m/PRIVMSG $chan :!short /i) {  
		print "####$input####\n";
		my $arg = $input;
		$arg =~ s/.*PRIVMSG $chan :!short //i;
		my $ret = shorten $arg;
		print $sock "PRIVMSG $out :$ret\r\n" if ($ret ne "");
		print "####Short called with URL: $arg | $ret####\n";
	}
	elsif ($input =~ m/PRIVMSG $chan :!wiki /i) {
		print "####$input####\n";
		my $arg = $input;
		$arg =~ s/.*PRIVMSG $chan :!wiki //i;
		my $ret = wiki $arg;
		print $sock "PRIVMSG $out :$ret\r\n" if ($ret ne "");
		print "####Wiki called with page: $arg | $ret####\n";

	}
	elsif ($input =~ m/PRIVMSG $chan :!wolfram /i) {
		print "####$input####\n";
		my $arg = $input;
		$arg =~ s/.*PRIVMSG $chan :!wolfram //i;
		my $ret = wolfram $arg;
		print $sock "PRIVMSG $out :$ret\r\n" if ($ret ne "");
		print "####Wolfram called with: $arg | $ret####\n";
	}
	elsif ($input =~ m/PRIVMSG $chan :!help /i) {
		print "####$input####\n";
		print $sock "PRIVMSG $out :Hi! I'm $nick! To use me, just type !short <VALID URL TO SHORTEN>, !wolfram <WOLFRAM|ALPHA INPUT>, or !wiki <WIKIPEDIA ARTICLE> and I'll PM you the result! For more information, see McSaucy!\r\n";
		print "####HELP called####\n";
	}
}


sub shorten($)
{
	my $url = shift;
	$url =~ s/[\n\r'"\\]//g;
	if ( $url !~ /http.?:\/\// )
	{		
		$url = "http://" . $url;
	}

	if (`curl -IL $url 2>/dev/null` !~ m/200 OK/) {
		#print "Invalid URL:  $url\[end]\n";
		return "";
	}

	my $raw_output = `curl \"http://api.bit.ly/shorten?longUrl=$url&login=<REDACTED>&apiKey=<REDACTED>\" 2>/dev/null`;
	my $output = $raw_output;
	$output =~ s/(.*shortUrl\": \")|(\"}}, \"statusCode.*)//g;
	if (`curl -IL $output 2>/dev/null` !~ m/200 OK/) {
		print "Verification failed: $output\[end]\n";
		return "";
	}
	return $output;
}

sub wiki($)
{
	my $page = shift;
	my $output = "";
	encode_entities($page);
	$page  =~ s/\s/_/g;
	print "$page\n";
	$output .= `curl --raw "http://en.wikipedia.org/w/api.php?format=xml&action=mobileview&page=$page&sections=0&noimages=yes&noheadings=yes&sectionprop=" 2>/dev/null`;
	chomp $output;

	return "" if $output =~ m/Wikimedia Error/;

	$output =~ s/[\n\r]/ /g;
	$output =~ s/\<\?.*\?\>//g;

	$output =~ s/\s+/ /g;

	decode_entities($output);

	$output =~ s/<table[^>]*>.*<\/table>//g;

	$output =~ s/<[^>]+>//g;

	$output =~ s/\s{2,}/ /g;
	
	$output =~ s/\[\s?[1234567890]+\s?\]//g;

	$output =~ s/^.{0,80}see .* \(disambiguation\)\.//g;

	$output =~ s/^\s+//g;

	return "" if ($output eq "");

	$output =~ s/&#160;/ /g;

	$output =~ s/ \( listen\)//g;

	if (length $output > 400) { $output =~ s/^(.{0,430}).*/$1\.\.\./; }

	return $output . " | " . shorten "http://en.wikipedia.org/wiki/$page";
}

sub wolfram($)
{
	my $query = shift;
	chomp $query;
	$query = uri_escape($query);

	my $raw = `curl --raw "http://api.wolframalpha.com/v2/query?input=$query&appid=<REDACTED>&format=plaintext" 2>/dev/null`;
	my $output = $raw;

	my $ret = "";
	$output =~ s/[\n\r]//g;
	$output =~ s/\s+/ /g;

	($ret) = $output =~ m/<pod[^>]+ primary='true'>[^x]+<plaintext>([^<]+)<\/plaintext>/i;

	decode_entities($ret);
	return "$ret";
}

