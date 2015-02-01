package JsonApi::Customer;

use lib $ENV{'PORTAHOME_WEB'}.'/apache/ls_json_api';
use Porta::Customer;
use parent 'JsonApi';


###################################################################################
# info

sub get_account_list
{
	use Porta::Account;

	my ($self,$p) = @_;
	$p->{limit} = (!$p->{limit} || $p->{limit}) > 100 ? 30 : $p->{limit};
	$p->{from} = $p->{from} || 0;
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $ac = new Porta::Account($ph);
	my $accounts_info = $ac->getlist({
		i_customer			=> $info->{i_customer},
		from				=> $p->{from},
		limit				=> $p->{limit},
		sip_status			=> $p->{filter} && $p->{filter}->{sip_status} || 'ANY',
		hide_closed_mode	=> $p->{filter} && $p->{filter}->{hide_closed_mode} || 1,
		real_accounts_mode	=> $p->{filter} && $p->{filter}->{real_accounts_mode} || 0,
	});
	my $output = {limit => $p->{limit}, from => $p->{from}, total_count => $accounts_info->{total_number}, subtotal_count => 0, filter => $p->{filter}, list => []};

	if(@{$accounts_info->{numbers_list}})
	{
		foreach my $account (@{$accounts_info->{numbers_list}})
		{$self->_dump($account);
			my $row = {
				balance => $self->_format_price($account->{balance}+($account->{credit_limit} ? $account->{credit_limit} : 0),$account->{iso_4217}),
				batch => $account->{batch},
				id => $account->{id},
				i_account => $account->{i_account},
				model => $account->{model},
				product => $account->{product},
				um_enabled => $account->{um_enabled},
			};
	    	$row->{status} = $self->_get_account_status($account);
			$row->{sip_status} = $ac->getSIPinfo($account->{id}) ? 'on' : 'off';
			push(@{$output->{list}},$row);
			++$output->{subtotal_count};
		}
	}

	return $output;
}

sub get_status
{
	my $self = shift;
	my $info = $self->_get('info');
	my $status = {value => 'ok', name => 'Ok'};

	if($info->{bill_closed})
	{
		$status = {value => 'closed', name => $self->_localize('closed')};
	}
	elsif($info->{blocked} eq 'Y')
	{
	    $status = {value => 'blocked', name => $self->_localize('blocked')};
	}
	elsif($info->{bill_suspended} && !$info->{bill_suspension_delayed})
	{
		$status = {value => 'suspended', name => $self->_localize('suspended')};
	}
	elsif($info->{status})
	{
		$status = {value => 'credit_exceed', name => $self->_localize('credit_exceed')};
	}
	elsif($info->{bill_suspension_delayed})
	{
		$status = {value => 'suspended', name => $self->_localize('suspended')};
	}
	elsif($info->{frozen})
	{
		$status = {value => 'frozen', name => $self->_localize('frozen')};
	}

	return $status;
}

1;