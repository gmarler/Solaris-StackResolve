package Solaris::StackResolve;
# ABSTRACT: Resolves user stacks for huge binaries on Solaris, gathered by DTrace
# VERSION

=head1

This module works to resolve user stacks collected by DTrace.

=cut

use Moose;
use Moose::Util::TypeConstraints;
with 'MooseX::Log::Log4perl';
use namespace::autoclean;
use Log::Log4perl qw(:easy);

# VERSION

use Storable;
use Math::BigInt qw();

# The file containing the unresolved user stack traces
has [ 'ustack_trace_file' ] => ( is => 'ro', isa => 'Str', required => 1);
# The filehandle for the above file
has [ 'ustack_trace_fh' ]   => ( is => 'ro', isa => 'IO::File',
                                 builder => '_build_ustack_trace_fh',
                                 lazy => 1, );
has [ 'dynamic_symtab'  ]   => ( is => 'ro', isa => 'HashRef' );
has [ 'static_symtab'  ]    => ( is => 'ro', isa => 'HashRef' );
# Combined dynamic + static symbol tables
has [ 'symtab'  ]           => ( is => 'ro', isa => 'HashRef' );
has [ 'nm_data' ]           => ( is => 'ro', isa => 'Solaris::nm' );
has [ 'pmap_data' ]         => ( is => 'ro', isa => 'Solaris::pmap' );

my $dynamic_sym_offset_href  = { };

# Open the file containing ustack() data to resolve
my $stack_fh = IO::File->new($ustack_trace_file, "<") or
   die "unable to open stack trace file";

my ($symtab,$dyn_symtab,$symcache) = ([], [], []);

  # sort and merge both static and dynamic symbols into $symtab
  @$symtab = sort {$a->[0] <=> $b->[0] } @$symtab, @$dyn_symtab;

# Look for duplicates
# TODO: Make this conditional
#my %dups;
#for (my $i = 0; $i < scalar(@$symtab); $i++) {
#  $dups{$symtab->[$i]->[0]}++;
#}
#foreach (sort { $dups{$a} <=> $dups{$b} } keys %dups) {
#  print "$_: $dups{$_}\n";
#}
 

my ($total_lookup,$symtab_entry,$cachehit,$cachemiss,$unresolved);

while (my $line = <$stack_fh>) {
  # Look up function name index - in cache first, if available
  my ($index);
  # symbol table entry pulled out of cache or full symbol table
  my ($symtab_entry);

  # If the line is a hex address, then try to resolve it
  if ($line =~ m{0x(?<hexaddr>[\da-fA-F]+)}) {
    # convert hex address to BigInt decimal
    my $dec_addr = Math::BigInt->from_hex($+{hexaddr});

    if (scalar(@$symcache) > 0) {
      $index = binarySearch($dec_addr, $symcache);
    }

    if ($index) {
      $symtab_entry = $symcache->[$index];
      $cachehit++;
    } else {
      $index = binarySearch($dec_addr, $symtab);
      if ($index) {
        $symtab_entry = $symtab->[$index];
        push @$symcache, $symtab_entry;
        # Sort the cache
        @$symcache = sort {$a->[0] <=> $b->[0] } @$symcache;
        $cachemiss++;
      }
    }

    # If we actually found the proper symbol table entry, make a pretty output
    # in the stack for it
    if ($symtab_entry) {
      my $funcname = $symtab_entry->[2];
      my $offset   = $symtab_entry->[1];
      my $resolved = sprintf("%s+0x%x",$funcname,$offset);
      $line =~ s{0x[\da-fA-F]+}{$resolved};
    } else {
      $unresolved++;
    }
    $total_lookup++;
  }
  print $line;
}

print "REPORT:\n";
my ($hit_pct,$miss_pct,$unres_pct) =
   (sprintf("%4.1f",($cachehit/$total_lookup)*100.0),
    sprintf("%4.1f",($cachemiss/$total_lookup)*100.0),
    sprintf("%4.1f",($unresolved/$total_lookup)*100.0));
print "CACHE HITS:            $cachehit  ($hit_pct%)\n";
print "CACHE MISSES:          $cachemiss  ($miss_pct%)\n";
print "UNRESOLVED:            $unresolved   ($unres_pct%)\n";
print "TOTAL LOOKUP ATTEMPTS: $total_lookup\n";

sub _binarySearch
{
  my ($address_to_resolve,$array) = @_;
  my ($midval);
  my ($mid) = Math::BigInt->new();

  my ($low, $high) = (Math::BigInt->new(0),
                      Math::BigInt->new(scalar(@$array) - 1));

  while ($low <= $high) {
    $mid    = ($low + $high) >> 1;
    $midval = $array->[$mid];

    if (($midval->[0] + $midval->[1]) < $address_to_resolve) {
      $low = $mid + 1;
    } elsif ($midval->[0] > $address_to_resolve) {
      $high = $mid - 1;
    } elsif (($address_to_resolve >= $midval->[0]) &&
             ($address_to_resolve <= ($midval->[0] + $midval->[1])))  {
      #$self->logger->debug( $midval->[0] . " <= $address_to_resolve <= " . ($midval->[0] + $midval->[1]) );
      return $mid;
    }
  }
  return; # undef
}




no Moose;
__PACKAGE__->meta->make_immutable;

1;
