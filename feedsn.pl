#!/usr/bin/env perl
#
# feedsn.pl
#
# Rick Umali (rickumali@gmail.com)
#
# V1.0 - 10/13/2007
#        Initial revision.
# V2.0 - 10/18/2007
#        Added support for dates.
# V3.0 - 11/04/2007
#        Finally fixed truncation
# V4.0 - 11/07/2007
#        Stopped writing to STDOUT
# V5.0 - 10/18/2008
#        Added bailout code to whileloop (search "bailout")
#
#
#
use strict;

use Date::Calc qw(Parse_Date Day_of_Week Day_of_Week_to_Text);
use Getopt::Long;
use WWW::Mechanize;
use HTML::TokeParser;
use XML::Writer;
use IO::File;
use XML::RSS;
use POSIX;

my $version = 4.0;
my $opt_debug = 0;
my $opt_version = 0;

GetOptions ('debug' => \$opt_debug,
            'version|v' => \$opt_version);

if ($opt_version) {
  print "feedsn.pl Version $opt_version\n";
  exit 1;
}

my $agent = WWW::Mechanize->new();
$agent->get("http://www.sportsblog.com/rickumali");

my $stream = HTML::TokeParser->new(\$agent->{content});
my %link = ();
my %subject = ();
my %text = ();
my %pubDate = ();
my $id_counter = 0;

while (my $article_tag = $stream->get_tag("article")) {
  $id_counter += 1;
  $link{$id_counter} = "http://www.sportsblog.com/rickumali";
  print "Found <article> " . $id_counter . "\n" if $opt_debug;
  $subject{$id_counter} = get_subject($stream);
  print "  Found subject: " . $subject{$id_counter} . "\n" if $opt_debug;
  $pubDate{$id_counter} = get_pubdate($stream);
  print "  Found date " . $pubDate{$id_counter} . "\n" if $opt_debug;
  $text{$id_counter} = get_entry($stream);
  print "  Found text " . $text{$id_counter} . "\n" if $opt_debug;

  while (my $div_tag = $stream->get_tag("div")) {
    if ($div_tag->[1]{class} && $div_tag->[1]{class} eq "article-entry-content") {
      $id_counter += 1;
      print "Found <div article-entry-content> " . $id_counter . "\n" if $opt_debug;
      my $anchor_tag = $stream->get_tag("a");

      print "  Found link: " . $anchor_tag->[1]{href} . "\n" if $opt_debug;
      $link{$id_counter} = $anchor_tag->[1]{href};
    }
  }
}

my $article_count = $id_counter;
my $pattern_length = length("By rickumali MMM. DD, YYYY");
for (my $i = 2; $i <= $article_count; $i++) {
  print "Walking: " . $link{$i} . "\n" if $opt_debug;
  $agent->get($link{$i});
  my $stream = HTML::TokeParser->new(\$agent->{content});
  while (my $article_tag = $stream->get_tag("article")) {
    print "Found <article>\n" if $opt_debug;
    $subject{$i} = get_subject($stream);
    print "  Found subject: " . $subject{$id_counter} . "\n" if $opt_debug;
    $text{$i} = get_entry($stream);
    $pubDate{$i} = substr $text{$i}, 0, $pattern_length;
    $pubDate{$i} = reformat_date($pubDate{$i});
    $text{$i} = substr $text{$i}, $pattern_length;
    print "Found text " . $text{$i} . "\n" if $opt_debug;
  }
}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
  gmtime(time);

my $feedname="rickonsports.rss";
my $rssDate = POSIX::strftime( "%a, %d %b %Y %H:%M:00 GMT", $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);

my $rss = new XML::RSS (version => '2.0');
$rss->channel(title          => 'Rick Umali: Sports On My Mind',
              link           => 'https://www.sportsblog.com/rickumali/',
              language       => 'en',
              description    => 'Rick Umali\'s Take on Sports',
              copyright      => 'Copyright 2007, rickumali.com',
              pubDate        => $rssDate,
              lastBuildDate  => $rssDate,
              docs           => 'http://feedvalidator.org/docs/rss2.html',
              managingEditor => 'rickumali@gmail.com',
              webMaster      => 'rickumali@gmail.com'
             );

$rss->image(title       => 'Rick Umali: Sports On My Mind',
            url         => 'http://www.rodrigoumali.com/rick05.jpg',
            link        => 'https://www.sportsblog.com/rickumali/',
            width       => 144,
            height      => 130,
            description => 'Rick Umali'
           );

for (my $id = 1; $id <= $article_count; $id++) {
    my $truncated_text = truncate_text($text{$id},160);
    $rss->add_item(title => $subject{$id},
                   link  => $link{$id},
                   pubDate  => $pubDate{$id},
                   permaLink  => $link{$id},
                   description => $truncated_text,
                  );
}

$rss->save($feedname);
# print "Generated $feedname with pubDate: $pubDate\n";

exit 0;

sub truncate_text() {
  my $text = shift;
  my $min_chars = shift; # Minimum number of characters for text

  if (length($text) < $min_chars) {
    return($text);
  }

  my $pos = 0;
  while ($pos < $min_chars) {
    $pos = index($text, " ", $pos+1);
    if ($pos == -1) {
      # This bailout code was added following an
      # outage I caused on rickumali.com. There are
      # some instances of this while() loop going into
      # an infinite loop. This bailout code catches
      # that. (10-19-2008)
      last;
    }
  }

  return(substr($text,0,$pos) . " ...");

}

sub get_subject() {
  my $stream = shift;
  my $subject = "No Subject";
  while (my $h1_tag = $stream->get_tag("h1")) {
    $subject = $stream->get_trimmed_text();
    return($subject);
  }
  return ($subject);
}

sub get_entry() {
  my $stream = shift;
  my $entry = "";
  my $keep_going = 1;
  while ($keep_going) {
    my $t = $stream->get_tag("p", "div");
    if ($t->[0] eq "div" and $t->[1]{class} eq "article-tags") {
      $keep_going = 0;
    } else {
      $entry .= $stream->get_phrase();
    }
  }
  return ($entry);
}

sub get_pubdate() {
  my $stream = shift;
  my $pub_date_raw = "No Entry";
  my $pub_date = "No Entry";
  while (my $div_tag = $stream->get_tag("div")) {

    if ($div_tag->[1]{class} && $div_tag->[1]{class} eq "articles-author-name") {
      $stream->get_tag("p");
      $pub_date_raw = $stream->get_phrase();
      $pub_date = reformat_date($pub_date_raw);
      return($pub_date);
    }
  }
  return ($pub_date_raw);
}

sub reformat_date() {
  # Read this raw date: By rickumali May. 13, 2017
  my $pub_date_raw = shift;

  # Remove the byline
  $pub_date_raw = substr $pub_date_raw, length("By rickumali") + 1;
  my ($raw_mon, $raw_day, $raw_year) = split(' ', $pub_date_raw);
  chop($raw_mon); # Remove trailing period
  chop($raw_day); # Remove trailing comma
  my $raw_time = "7:00"; # Hardcoded
  my $raw_merid = "PM"; # Hardcoded
  my $new_raw = $raw_mon . " " . $raw_day . " " . $raw_year;
  my ($year, $month, $day) = Parse_Date($new_raw);
  my $dow = Day_of_Week($year, $month, $day);
  my $today = Day_of_Week_to_Text($dow);
  if ($raw_merid eq "PM") {
    my ($hour,$min) = split(":", $raw_time);
    $hour+=12;
    if ($hour == 24) {
      $hour = 12;
    }
    $raw_time=sprintf("%02s:%02s",$hour,$min);
  }

  # Generate this format: Sat, 07 Sep 2002 9:42:31 GMT
  return(sprintf("%.3s, %s %s %s %s:00 EDT", 
    $today,$raw_day,$raw_mon,$year,$raw_time));
}
