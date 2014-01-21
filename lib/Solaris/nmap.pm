package Solaris::nm;

use Moose;
use Moose::Util::TypeConstraints;
with 'MooseX::Log::Log4perl';
use namespace::autoclean;
use Log::Log4perl qw(:easy);

# VERSION

has [ 'binary' ]             => ( is  => 'ro', isa => 'Str', required => 1, );
# Can't use builder here, because we must be sure the pid attribute has already
# been set; so we use an after clause
has [ 'static_symtab' ]  => ( is  => 'ro', isa => 'ArrayRef',
                              builder => '_build_static_symtab',
                              lazy => 1, );

sub _build_static_symtab {
  my ($self) = shift;

  my ($static_symtab_aref)         = [ ];

  my $binary = $self->binary;
  # TODO: Implement Perl equivalent of:
  # /usr/ccs/bin/nm -C /bb/bin/m_wsrusr.tsk |
  #  nawk -F'|' '$4 ~ /^FUNC/ { print $2, $3, $NF }' |
  #  sort -nk 1,1 > /tmp/m_wsrusr.syms
  my @cmd = ( qq(/usr/ccs/bin/nm), qq(), qq($binary) );

  # TODO: Split STDOUT from STDERR - in case we have an issue, we'll want them seperate
  my $c = qx{@cmd};

  # TODO: Validate the return code above was good
#  while ($c =~ m{$so_regex}gsmx) {
#    if (not exists $dynamic_sym_offset_href->{$2}) {
#      $dynamic_sym_offset_href->{$2} = hex($1);
#    }
#  }
 

  return $static_symtab_aref;
}


no Moose;
__PACKAGE__->meta->make_immutable;


1;
