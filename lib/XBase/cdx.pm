
=head1 NAME

XBase::cdx - Support for compound index files

=head1 SYNOPSIS

Used indirectly, via XBase.

=head1 DESCRIPTION

To be worked on.

=head1 VERSION

0.03

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), XBase(3)

=cut


# ##################################
# Here starts the XBase::cdx package

package XBase::cdx;

use strict;
use XBase::Base;


use vars qw( $VERSION @ISA );
@ISA = qw( XBase::Base );


$VERSION = "0.03";

sub read_header
	{
	my $self = shift;

	my $header;
	$self->{'fh'}->read($header, 512) == 512 or do
		{ Error "Error reading header of $self->{'filename'}\n";
		return; };

	my ($root_page1, $root_page2, $free_list, $version, $key_len,
		$index_opts, $index_sign, $reserved1, $sort_order,
		$total_exp_len, $for_exp_len, $reserved2, $key_exp_len)
		= unpack "nnNNvCCA486vvvvv", $header;

	my $root_page = $root_page1 | ($root_page2 << 16);

	@{$self}{ qw( root_page free_list version key_len index_opts
		index_sign sort_order total_exp_len for_exp_len
		key_exp_len ) }
			= ($root_page, $free_list, $version, $key_len,
			$index_opts, $index_sign, $sort_order,
			$total_exp_len, $for_exp_len, $key_exp_len);

	1;
	}

1;

