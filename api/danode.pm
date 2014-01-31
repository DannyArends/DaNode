package api::danode;
use strict;
use Exporter 'import';
use URI::Escape;

our @EXPORT = qw/&toS $_GET $_POST/;
our $_GET  = getGET();
our $_POST = getPOST();

sub getGET{
  my $pref = {};
  foreach my $p (@ARGV){
    my @array = split(/=/,$p);
    $pref->{$array[0]} = uri_unescape($array[1]);
  }
  return $pref;
}

sub toS{
  my $HREF = shift;
  my $ret = "[";
  my $cnt = keys(%$HREF);
  for(keys %$HREF){ 
    $ret .= "\"" . $_ . "\":\"" . $HREF->{$_} . "\"";
    if($cnt > 1){ $ret .= ", "; $cnt--; }
  }
  $ret .= "]";
  return $ret;
}

sub getPOST{
  my $pref = {};
  if(not(-t STDIN)){
    my @lines = <STDIN>;
    foreach my $line (@lines){
      chomp($line);
      my @array = split(/=/,$line);
      $pref->{$array[1]} = uri_unescape($array[2]);
    }
  }
  return $pref;
}

return 1;
