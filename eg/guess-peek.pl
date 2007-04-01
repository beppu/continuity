#!/usr/bin/perl

use lib '../lib';
use strict;
use warnings;
use Continuity;

my $server = new Continuity(
      port => 8080,
      ip_session => 0,
      cookie_session => 'sid',
      path_session => 1,
);
$server->loop;

sub getNum {
  my $request = shift;
  $request->print( qq{
    Enter Guess: <input name="num" id=num>
    <script>document.getElementById('num').focus()</script>
    </form>
    </body>
    </html>
  });
  $request = $request->next;
  my $num = $request->param('num');
  return $num;
}

sub peek {
  my ($request) = @_;
  while(1) {
    my $sessions = $server->{mapper}->{sessions};
    $request->print(sprintf "Session count: %d<br>\n", scalar keys %$sessions);
    my $sess;
    my $inspector = Inspector->new( callback => sub {
      use PadWalker 'peek_my';
      for my $i (1..100) { 
print STDERR "bjork\n";
        my $vars = peek_my($i) or last;
        next unless exists $vars->{'$number'};
        $request->print("$sess: secret number: ", ${ $vars->{'$number'} }, "<br>\n");
        last;
      }
    });
    foreach $sess (keys %$sessions) {
      # next unless $sess =~ /^\.\./;
      next if $sess =~ /peek/;  # don't try to peek on ourself.  that would be bad.
      $inspector->inspect( $sessions->{$sess} );
    }
    $request->next;
  }
}

sub main {
  my $request = shift;
  $request->next;

  my $path = $request->request->url->path;
  print STDERR "Path: '$path'\n";

  # If this is a request for the pushtream, then give them that
  if($path =~ /^\/peek/) {
    peek($request);
  }

  while(1) {
    my $guess;
    my $number = int(rand(100)) + 1;
    my $tries = 0;
    my $out = qq{
      <html>
        <head><title>The Guessing Game</title></head>
        <body>
          <form method=POST>
            Hi! I'm thinking of a number from 1 to 100... can you guess it?<br>
    };
    do {
      $tries++;
      do {
        $request->print($out);
        $guess = getNum($request);
      } until ($guess > 0);
      $out .= "It is smaller than $guess.<br>\n" if $guess > $number;
      $out .= "It is bigger than $guess.<br>\n" if $guess < $number;
    } until ($guess == $number);
    $request->print("You got it! My number was in fact $number.<br>\n");
    $request->print("It took you $tries tries.<br>\n");
    $request->print('<a href="/">Try Again</a>');
    $request->next;
}}

package Inspector;
use Data::Dumper;
use Coro::Event;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = { 
    peeks_pending => \my $peeks_pending, 
    requester => $args{requester},
    callback => $args{callback},
  };
  bless $self, $class;
  return $self;
}

sub inspect {
    my $self = shift;
    my $queue = shift;
    ${ $self->{peeks_pending} } = 1;
    $queue->put($self);
    my $var_watcher = Coro::Event->var( var => $self->{peeks_pending}, poll => 'w', );
    while( ${ $self->{peeks_pending} } ) {
print STDERR "spin\n";
        $var_watcher->next;
print STDERR "spun\n";
    }
    $var_watcher->stop;
    $var_watcher->cancel;
    return undef;
}

sub immediate {
  my $self = shift;
  my $requester = $self->{requester};
  $self->{callback}->(requester => $requester); # XXX API?  pass $self and solidify?  or just pass a few vars?
  ${ $self->{peeks_pending} } = 0;
  return 1;
}

sub end_request { }

1;

