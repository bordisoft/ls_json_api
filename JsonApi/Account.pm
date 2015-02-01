package JsonApi::Account;

use lib $ENV{'PORTAHOME_WEB'}.'/apache/ls_json_api';
use Porta::Account;
use parent 'JsonApi';


###################################################################################
# info

sub get_subscriber
{
	my ($self,$args) = @_;
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $obj = $self->_get('obj');
	my $subs = $obj->getSubscriber($info->{i_subscriber});
	my $fields = ['companyname', 'salutation', 'firstname', 'midinit', 'lastname', 'baddr1', 'state', 'zip',
		'city', 'country', 'cont1', 'phone1', 'faxnum', 'phone2', 'cont2', 'note'];
	my $output = {};

	$args = ref($args) eq "ARRAY" && @$args ? $args : $fields;
	foreach my $attribute(@$args)
	{
		my $access = $self->_get_access($attribute);
		if($access && !defined $output->{$attribute})
		{
			my $value;
			my $attribute_properties = $self->_attribute_properties($attribute);
			if(defined $subs->{$attribute})
			{
				$value = $subs->{$attribute};
				if(defined $attribute_properties && defined $attribute_properties->{format})
				{
					if('price' eq $attribute_properties->{format} && $access eq 'read')
					{
						$value = $self->_format_price($value);
					}
					elsif($self->_in_array(['date','time','date_time'],$attribute_properties->{format}))
					{
						$value = $self->_format_datetime($ph->{'out_'.$attribute_properties->{format}.'_format'},$value);
					}
				}
			}
			else
			{
				$value = $access eq 'update' ? '' : $self->_localize('none');
			}
			$output->{$attribute} = {
				value => $value,
				access => $access,
				title => $self->_localize($attribute)
			};
		}
	}

	return $output;
}

sub set_subscriber
{
	my ($self,$args) = @_;

	die "400 no arguments to set subscriber info" if(!%$args);

	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $obj = $self->_get('obj');
	my $fields = ['companyname', 'salutation', 'firstname', 'midinit', 'lastname', 'baddr1', 'state', 'zip',
		'city', 'country', 'cont1', 'phone1', 'faxnum', 'phone2', 'cont2', 'email', 'note'];
	my $hash = $self->_validate_args($args,$fields);
	$hash->{i_subscriber} = $info->{i_subscriber};
	$obj->updateSubscriber($hash, $ph->{i_account});
	$self->_set('info',$obj->get($info->{i_account}, {get_services => 1}));

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

sub get_aliases
{
	my ($self,$args) = @_;

	die "403 no permissions to access aliases" if(!($self->_get_access({attr => '*', obj => 'Account_Aliases'})));

	$args = ref($args) eq "HASH" ? $args : {};
	$args->{from} = defined $args->{from} ? $args->{from} : 0;
	$args->{limit} = defined $args->{limit} && $args->{limit} < 30 ? $args->{limit} : 30;
	my $obj = $self->_get('obj');
	my $info = $self->_get('info');
	my $output = {
		total => $obj->count_aliases({i_master_account => $info->{i_account}}),
		from => $args->{from},
		limit => $args->{limit},
		list => []
	};

	if($output->{total})
	{
		$output->{list} = $obj->get_alias_list({
			i_master_account => $info->{i_account},
	        pager            => $output->{limit},
			from             => $output->{from},
		});
	}

	return $output;
}

sub set_aliases
{
	my ($self,$args) = @_;

	die "403 no permissions to update aliases" if(!($self->_get_access({attr => '*', obj => 'Account_Aliases'})));
	die "400 no arguments to update aliases" if ref($args) ne "HASH" || !defined $args->{action} || !($self->_in_array(['add','delete'],$args->{action}));

	my $info = $self->_get('info');
	my $obj = $self->_get('obj');
	if('add' eq $args->{action})
	{
		my @params = qw(alias_id alias_blocked);
		foreach(@params) { die "400 $_ is mandatory to update aliases" if !defined $args->{$_}; }
		my $alias_i_account = $obj->add_alias({
			'id'               => $args->{alias_id},
			'blocked'          => $args->{alias_blocked},
			'i_master_account' => $info->{i_account},
			'info'             => $info,
		});
		$args->{action} = 'delete' if defined $args->{alias_i_account};
	}
	if('delete' eq $args->{action})
	{
		my @params = qw(alias_i_account);
		foreach(@params) { die "400 $_ is mandatory to update aliases" if !defined $args->{$_}; }
		$obj->delete_alias({
			'alias_i_account'	=> $args->{alias_i_account},
			'i_master_account'	=> $info->{i_account},
		});
	}

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

sub get_status
{
	my $self = shift;
	my $info = $self->_get('info');

	my $status = $self->_get_status("Account",$info);

	return {value => $status, access => "read", name => ("ok" eq $status ? "Ok" : $self->_localize($status))};
}


###################################################################################
# payment

sub set_voucher_topup
{
	my ($self,$args) = @_;

	die "400 no arguments to topup using voucher" if(ref($args) ne "HASH" || !$args->{voucher});

	my $obj = $self->_get('obj');
	my $ph = $self->_get('ph');
    my $result;

 	eval
 	{
	    $result = $obj->topup_using_voucher({
			i_account	=> $ph->{i_account},
			voucher_id	=> $args->{voucher},
			history		=> ''
		});
    };

	die "605 invalid voucher" if ($@);

	$self->_set('info',$obj->get($ph->{i_account}, {get_services => 1}));
	my $info = $self->_get('info');
	my $new_balance = abs(("Debit" eq $info->{bm_name} ? $info->{balance} : ($info->{credit_limit} ? $info->{credit_limit} : 0) - $info->{balance}));
	my $p = {
		amount => $self->_format_price($result->{amount}),
		new_balance => $self->_format_price($new_balance)
	};

	return {success => $self->_localize({msg => 'voucher_recharged',p => $p})};
}


###################################################################################
# features

sub get_followme_info
{
	use Porta::FollowMe;

	my $self = shift;
	my $ph = $self->_get('ph');
	my $followme = new Porta::FollowMe($ph);
    my $followme_info = $followme->get({i_account => $ph->{i_account}});
    my $output = {};
    my $follow_me_enabled_access = $self->_get_access({attr => 'follow_me_enabled', obj => 'Accounts'});
    if($follow_me_enabled_access)
    {
	   	$output->{follow_me_enabled} = {
	    	name => $self->_localize("follow_me_enabled"),
	    	access => $follow_me_enabled_access
	    };
	    my $options = $self->_get_options("follow_me_enabled");
	    if("update" eq $follow_me_enabled_access)
    	{
			$output->{follow_me_enabled}->{value} = $options;
    	}
    	else
    	{
	    	foreach(@$options)
	    	{
	    		if($_->{sel})
	    		{
	    			$output->{follow_me_enabled}->{value} = $_->{name};
	    			last;
	    		}
	    	}
    	}
    }
    my $max_forwards_access = $self->_get_access({attr => 'max_forwards', obj => 'Follow_Me'});
    $output->{max_forwards} = {
    	name => $self->_localize("max_forwards"),
    	access => $max_forwards_access,
    	value => $followme_info->{max_forwards}
    } if $max_forwards_access;
    my $timeout_access = $self->_get_access({attr => 'timeout', obj => 'Follow_Me'});
    $output->{timeout} = {
        name => $self->_localize("timeout"),
    	access => $timeout_access,
    	value => $followme_info->{timeout}
    } if $timeout_access;
    my $sequence_access = $self->_get_access({attr => 'sequence', obj => 'Follow_Me'});
	if($sequence_access)
	{
		$output->{sequence} = {
	    	name => $self->_localize("sequence"),
	    	access => $sequence_access
	    };
    	my $options = $self->_get_options("sequence");
    	if("update" eq $sequence_access)
    	{
			$output->{sequence}->{value} = $options;
    	}
    	else
    	{
	    	foreach(@$options)
	    	{
	    		if($_->{sel})
	    		{
	    			$output->{sequence}->{value} = $_->{name};
	    			last;
	    		}
	    	}
    	}
	}

	die "403 no permissions to access FollowMe info " if !%$output;

	return $output;
}

sub get_followme_numbers
{
	my ($self,$args) = @_;
    my $info = $self->_get("info");

    die "403 no permissions to access FollowMe numbers" if $info->{follow_me_enabled} eq "N" || !($self->_get_access({attr => '*', obj => 'Follow_Me_Numbers'}));

	my $limit = defined $args->{limit} && $args->{limit} <= 30 ? $args->{limit} : 30;
   	my $from = defined $args->{from} || 0;

	my @attributes = qw(i_follow_me i_follow_me_number redirect_number timeout keep_original_cli);
	my @_attributes;
	if($info->{follow_me_enabled} eq "Y" || $info->{follow_me_enabled} eq "F")
	{
		@_attributes = qw(name i_follow_order period period_description active);
		@_attributes = (@_attributes,qw(domain use_tcp keep_original_cld)) if $info->{follow_me_enabled} eq "F";
	}
	elsif($info->{follow_me_enabled} eq "U" || $info->{follow_me_enabled} eq "C")
	{
		@_attributes = qw(keep_original_cld max_sim_calls);
		@_attributes = (@_attributes,qw(domain use_tcp)) if $info->{follow_me_enabled} eq "U";
	}
	@attributes = (@attributes,@_attributes);
	my $editable = 0;
	my $access = {};
	foreach(@attributes) {
		$access->{$_} = $self->_get_access({attr => $_, obj => 'Follow_Me_Numbers'});
		$editable = $editable ? $editable : ("update" eq $access->{$_} ? 1 : 0);
	}
	my $output = {
		list => [],
		total_count => 0,
		subtotal_count => 0,
		from => $from,
		limit => $limit
	};

	my $sql_total = "SELECT COUNT(*) as total_count FROM Follow_Me_Numbers WHERE i_account = $info->{i_account}";
	my $st = undef;
	eval { $st = Porta::SQL->prepareNexecute({ sql => $sql_total }, 'porta-billing-slave');
	1 } or die "500 sql error";
	if($st) { while (my $data = $st->fetchrow_hashref) { $output->{total_count} = $data->{total_count}; } }

	if($output->{total_count})
	{
		my $keep_original_cli = [
			{ value => 'Y', name => $self->_localize('caller_number_and_name') },
			{ value => 'I', name => $self->_localize('caller_number_and_forwarder_name') },
			{ value => 'N', name => $self->_localize('forwarder_number_and_name') },
		];
		my $sql = "SELECT * FROM Follow_Me_Numbers WHERE i_account = $info->{i_account} ORDER BY i_follow_order ASC LIMIT $limit OFFSET $from";
		$st = undef;
		eval { $st = Porta::SQL->prepareNexecute({ sql => $sql }, 'porta-billing-slave');
		1 } or die "500 sql error";
		if($st) { while (my $data = $st->fetchrow_hashref) {
			my $row = {};
			foreach(@attributes) {
				if($_ eq "keep_original_cli")
				{
					my $_value;
					foreach my $k(@$keep_original_cli)
					{
						if("update" eq $access->{keep_original_cli})
						{
							$_value = [] if !defined $_value;
							push @$_value,{value => $k->{value}, name => $k->{name}, sel => ($data->{keep_original_cli} eq $k->{value} ? 1 : 0)};
						}
						elsif($data->{keep_original_cli} eq $k->{value})
						{
							$_value = $k->{name};
							last;
						}
					}
					$row->{keep_original_cli} = $_value;
					next;
				}
				$row->{$_} = $data->{$_};
			}
			$row->{editable} = $editable;
			push @{$output->{list}}, $row;
			++$output->{subtotal_count};
		}}
	}

	return $output;
}

sub set_followme_info
{
	my ($self,$args) = @_;

	die "400 no arguments to access FollowMe info" if(ref($args) ne "HASH");

	my $ph = $self->_get('ph');
	my $fields = ["max_forwards","timeout","sequence","follow_me_enabled"];
	my $hash = $self->_validate_args($args,$fields);

	use Porta::FollowMe;

	my $ph = $self->_get('ph');
	my $followme = new Porta::FollowMe($ph);
    my $followme_info = $followme->get({i_account => $ph->{i_account}});
    if(defined $hash->{follow_me_enabled})
	{
		my $info = $self->_get('info');
		my $follow_me_enabled = $info->{follow_me_enabled};
		$self->set_attributes({follow_me_enabled => $hash->{follow_me_enabled}});
		if("N" eq $hash->{follow_me_enabled}
			|| !($self->_in_array(["Y","F"],$follow_me_enabled) && $self->_in_array(["Y","F"],$hash->{follow_me_enabled}))
			|| !($self->_in_array(["U","C"],$follow_me_enabled) && $self->_in_array(["U","C"],$hash->{follow_me_enabled})))
		{
			$followme->delete_numbers({i_account => $ph->{i_account}})
		}
		delete $hash->{follow_me_enabled};
		return {success => $self->_localize('SUCCESS_UPDATED')} if !%$hash;
	}
	$hash->{i_account} = $ph->{i_account};
    if($followme_info->{i_follow_me})
    {
    	$hash->{i_follow_me} = $followme_info->{i_follow_me};
    	$followme->update($hash);
    }
    else
    {
    	$followme->add($hash);
    }

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

sub set_followme_number
{
	my ($self,$args) = @_;
    my $info = $self->_get("info");

    die "403 no permissions to update FollowMe number" if $info->{follow_me_enabled} eq "N" || !($self->_get_access({attr => '*', obj => 'Follow_Me_Numbers'}));

	my @attributes = qw(i_follow_me_number redirect_number timeout keep_original_cli);
	my @_attributes;
	if($info->{follow_me_enabled} eq "Y" || $info->{follow_me_enabled} eq "F")
	{
		@_attributes = qw(name i_follow_order period period_description active);
		@_attributes = (@_attributes,qw(domain use_tcp keep_original_cld)) if $info->{follow_me_enabled} eq "F";
	}
	elsif($info->{follow_me_enabled} eq "U" || $info->{follow_me_enabled} eq "C")
	{
		@_attributes = qw(keep_original_cld max_sim_calls);
		@_attributes = (@_attributes,qw(domain use_tcp)) if $info->{follow_me_enabled} eq "U";
	}
	@attributes = (@attributes,@_attributes);
	my $hash = {};
	foreach(@attributes) {
		die "403 no update access for $_" if ("i_follow_me_number" ne $_ && defined $args->{$_} && "update" ne $self->_get_access({attr => $_, obj => 'Follow_Me_Numbers'}));
		die "400 $_ not defined in \$args"  if ("i_follow_me_number" ne $_ && !$args->{$_} && "update" eq $self->_get_access({attr => $_, obj => 'Follow_Me_Numbers'}));
		$hash->{$_} = $args->{$_};
	}

	use Porta::FollowMe;

	my $ph = $self->_get('ph');
	$hash->{i_account} = $ph->{i_account};
	my $followme = new Porta::FollowMe($ph);
	my $followme_info = $followme->get({i_account => $ph->{i_account}});

	die "403 FollowMe instance does not exist" if !$followme_info->{i_follow_me};
	die "400 domain is not allowed" if(defined $hash->{domain} && !$followme->validate_number_domain($hash));

	$hash->{i_follow_me} = $followme_info->{i_follow_me};
	$hash->{keep_original_cld} = "N" if (!defined $hash->{keep_original_cld} || !$self->_in_array(["Y","N"],$hash->{keep_original_cld}));
	if(defined $hash->{i_follow_me_number}) { $followme->update_number($hash); }
	else { $followme->add_number($hash); }

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

1;