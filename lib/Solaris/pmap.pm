package Solaris::pmap;

use version 0.77; our $VERSION = version->declare("v0.0.1");

use Moose;
use Moose::Util::TypeConstraints;
with 'MooseX::Log::Log4perl';
use namespace::autoclean;
use Log::Log4perl qw(:easy);

has [ 'pid' ]             => ( is  => 'ro', isa => 'Num', required => 1, );
has [ 'dynamic_symtab' ]  => ( is  => 'ro', isa => 'ArrayRef',
                               builder => '_build_dynamic_symtab' );

sub _build_dynamic_symtab {
  my ($self) = shift;

  my $so_regex = qr{
                     ^ ([0-9a-fA-F]+)            \s+ # Hex starting address
                       \S+                       \s+ # size
                       \S+                       \s+ # perms
                       (/[^\n]+?\.so(?:[^\n]+|)) \n  # Full path to .so* file
                   }smx;
  my ($dynamic_sym_offset_href,$dyn_symtab_aref);

  my @cmd = ( qq(/usr/bin/pmap), qq($self->pid) );

  # TODO: There are times when the process is manipulating the address space
  #       so quickly that pmap can't grab the process - in those cases, we should
  #       try more than once, noting each time we loop, before giving up.
  # TODO: Split STDOUT from STDERR - in case we have an issue, we'll want them seperate
  my $c = qx{@cmd};

  # TODO: Validate the return code above was good
  while ($c =~ m{$so_regex}gsmx) {
    if (not exists $dynamic_sym_offset_href->{$2}) {
      $dynamic_sym_offset_href->{$2} = hex($1);
    }
  }
  
  foreach my $libpath (keys %$dynamic_sym_offset_href) {
    print "Building symtab for $libpath\n";
    my $base_addr = $dynamic_sym_offset_href->{$libpath};
    my @cmd       = ( q{/usr/ccs/bin/nm}, q{-C}, qq{$libpath} );
    my $out       = qx{@cmd};

    # TODO: Validate the return code above was good
    while ($out =~ m{^ [^|]+ \|
                       \s+? (\d+) \|   # Offset from base
                       \s+? (\d+) \|   # Size
                       FUNC \s+   \|   # It's a Function!
                       [^|]+      \|
                       [^|]+      \|
                       [^|]+      \|
                       ([^\n]+) \n
                    }gsmx) {
      # create the start address from the library base + offset
      my $val = [ $base_addr + $1, $2, $3 ];
      push @$dyn_symtab_aref, $val;
    }
  }

  return $dyn_symtab_aref;
}


no Moose;
__PACKAGE__->meta->make_immutable;


1;
