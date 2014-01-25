package Solaris::StackResolve;

use Moose;
use Moose::Util::TypeConstraints;
with 'MooseX::Log::Log4perl';
use namespace::autoclean;
use Log::Log4perl qw(:easy);
use autodie;
use Storable;
use Math::BigInt  qw();
use IO::File      qw();

# ABSTRACT: Resolves user stacks for huge binaries on Solaris, gathered by DTrace
# VERSION

=head1

This module works to resolve user stacks collected by DTrace.

=cut

# PID we will be DTrace'ing and resolving the user stacks for
has [ 'pid' ]               => ( is => 'ro', isa => 'Num', required => 1);
# Location of 'hacked' DTrace binary that doesn't resolve ustack()'s
has [ 'dtrace' ]            => ( is => 'ro', isa => 'Str', required => 1);
# The file containing the unresolved user stack traces
has [ 'ustack_trace_file' ] => ( is => 'ro', isa => 'Str',
                                 builder => '_build_ustack_trace_file',
                                 lazy => 1, );
# The filehandle for the above file
has [ 'ustack_trace_fh' ]   => ( is => 'ro', isa => 'IO::File',
                                 builder => '_build_ustack_trace_fh',
                                 lazy => 1, );
# Data from which dynamic/static symbol tables are extracted
# TODO: make builders for these
has [ 'nm_data' ]           => ( is => 'ro', isa => 'Solaris::nm' );
has [ 'pmap_data' ]         => ( is => 'ro', isa => 'Solaris::pmap' );
# Combined dynamic + static symbol tables
has [ 'symtab'  ]           => ( is => 'ro', isa => 'HashRef' );
has [ 'dynamic_symtab'  ]   => ( is => 'ro', isa => 'HashRef' );
has [ 'static_symtab'  ]    => ( is => 'ro', isa => 'HashRef' );
# Statistics of use
has [ 'cachehit' ]          => ( is => 'rw', isa => 'Num' );
has [ 'cachemiss' ]         => ( is => 'rw', isa => 'Num' );
has [ 'unresolved' ]        => ( is => 'rw', isa => 'Num' );
has [ 'total_lookup' ]      => ( is => 'rw', isa => 'Num' );

=head1 DESCRIPTION

Solaris::StackResolve is used for resolving the symbols for userspace stacks
captured purposely unresolved from very large binaries (think > 500 MB in size).

Such stacks are captured from DTrace's ustack() action, which normally will
resolve the stacks to their symbols on the fly.  For very large binaries,
this can take an extremely long time (minutes), so trying to capture several
hundred stacks a second can prove to be an exercise in futility.

Using a hacked version of libdtrace that doesn't resolve ustack() symbols at
all, just providing numbers.

So, this module automates the following steps, given a process PID to work on:

=over

=item

Produce the name of the file to contain the unresolved user stacks

=item

Start the DTrace to gather the data into that file.

=item

Run a pmap via B<Solaris::pmap>

This gets the list of dynamic symbols for the binary

=item

Run an nm via B<Solaris::nm>

This gets a list of static symbols for the binary

=item

Produce a combined symbol lookup table

=item

Upon termination of the DTrace capture:

Resolve all symbols to a "resolved" variant of the output file and exit.

=back

=cut


=head1 METHODS

=cut

sub _build_ustack_trace_file {
  my ($self) = shift;

  return "/tmp/junk_trace_file.out";
}

sub _build_ustack_trace_fh {
  my ($self) = shift;

  my $file = $self->ustack_trace_file;
  if ( not -f $file ) {
    die "__PACKAGE__: $file does not exist";
  }
  my $fh = IO::File->new($file,"<") or
    die "Unable to open $file";

  $self->ustack_trace_fh($fh);
}

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
      $index = $self->_binarySearch($dec_addr, $symcache);
    }

    if ($index) {
      $symtab_entry = $symcache->[$index];
      $cachehit++;
    } else {
      $index = $self->_binarySearch($dec_addr, $symtab);
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

=head2 $ustack_res_obj->report()

Produce a report concerning the efficiency/performance of the lookup process
for this particular run.

=cut

sub report {
  my ($self) = shift;

  my ($cachehit,$cachemiss,$unresolved,$total_lookup) =
    ($self->cachehit,$self->cachemiss,$self->unresolved,$self->total_lookup);

  $self->logger->info("REPORT:");
  my ($hit_pct,$miss_pct,$unres_pct) =
     (sprintf("%4.1f",($cachehit/$total_lookup)*100.0),
      sprintf("%4.1f",($cachemiss/$total_lookup)*100.0),
      sprintf("%4.1f",($unresolved/$total_lookup)*100.0));

  $self->logger->info("CACHE HITS:            $cachehit  ($hit_pct%)");
  $self->logger->info("CACHE MISSES:          $cachemiss  ($miss_pct%)");
  $self->logger->info("UNRESOLVED:            $unresolved   ($unres_pct%)");
  $self->logger->info("TOTAL LOOKUP ATTEMPTS: $total_lookup");
}

=head2 _binarySearch

For userspace symbol lookups, does a correct binary search to place a raw
address in userspace inside the range of some function.

=cut

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
