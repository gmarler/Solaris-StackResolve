package Solaris::nm;

use Moose;
use Moose::Util::TypeConstraints;
with 'MooseX::Log::Log4perl';
use namespace::autoclean;
use Log::Log4perl qw(:easy);

use IPC::Run qw(start pump);

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

  my $nm_regex     = qr{^ ( [^\n]+ ) \n
                          # Up to, but not including, the next line
                          (?= ^ [\n]+ \n )
                       }smx;
  my $nm_regex_eof = qr{^ ([^\n]+?) (?:\n|\n\z)}smx;
  my $nm_regex2     = qr{^[^|\s]+ \s+?  |
                          \s+? (?<start>[^|\s]+) \s+? |  # Address
                          \s+? (?<size>[^|\s]+)  \s+? |  # length
                          \s+? FUNC \s+? |
                          [^|]+ |
                          [^|]+ |
                          [^|]+ |
                          \s+? (?<func>[^\n]+?) \n
                        }smx;
  my $nm_regex_eof2 = qr{^ ([^\n]+?) (?:\n|\n\z)}smx;

  # TODO: Implement Perl equivalent of:
  # /usr/ccs/bin/nm -C /bb/bin/m_wsrusr.tsk |
  #  nawk -F'|' '$4 ~ /^FUNC/ { print $2, $3, $NF }' |
  #  sort -nk 1,1 > /tmp/m_wsrusr.syms
  my ($in, $out, $err);
  my @cmd = ( qq(/usr/ccs/bin/nm), qq(-C), qq($binary) );

  # TODO: Split STDOUT from STDERR - in case we have an issue, we'll want them seperate
  #my $c = qx{@cmd};
  my $h = start \@cmd, \$in, \$out, \$err;

  while ($h->pumpable) {
    if ($h->pump) {
      if (length $out) {
        # Extract as many whole data lines as possible, process, then
        # continue on
        my (@subs,@tmp);
        # If we're at the end of the file, then we need to use a special case regex
        @subs = $out =~ m{ $nm_regex_eof2 }gsmx;
        if (@subs) {
          my ($drops);
          for (my $i = 0; $i < scalar(@subs); $i++) {
            my @vals =
              map { / (\S+) /x }
              split /\|/, $subs[$i], -1;
            if ( (scalar(@vals) == 8) and
                 ($vals[3] eq "FUNC") ) {
              my $val = [ $vals[1], $vals[2], $vals[7] ];
              $self->logger->warn(join(', ',@$val));
              push @tmp, $val;
            }
          }

          push @$static_symtab_aref, @tmp;

          # Delete what we've parsed so far from our contents buffer...
          $drops = $out =~ s{ $nm_regex_eof2 }{}gsmx;
          $self->logger->warn( "Processed $drops lines" );
        }
      } else {
        next;
      }
    } else {
      $h->finish;
      last;
    }
  }


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
