package JsonApi;

use lib $ENV{'PORTAHOME_WEB'}.'/apache/ls_json_api';
use parent 'JsonApi::Internal';
use Try::Tiny;

my $debug = 1;

sub new
{
	my $self = shift;
	my $ph = shift;
	my $realm = $ENV{JSON_Api_Realm};
	my $module = 'Porta::'.$realm;
	my $obj = new $module($ph);
	my $info = $realm eq 'Account' ? $obj->get($ph->{i_account}, {get_services => 1}) : $obj->get($ph->{i_customer}, 0,  {get_services => 1});

	$self->_set('ph',$ph);
	$self->_set('realm',$realm);
	$self->_set('obj', $obj);
	$self->_set('info', $info);
	$self->_set('options_list', {});
	$self->_set('access', {});
	$self->_set('locale', {});

	return $self;
}

sub call
{
	my ($self,$set_requests,$get_requests) = @_;
	my @response_types = qw(notice success warning);
	my $response = {};
	my $requests = [];
	push @$requests, $set_requests if @$set_requests;
	push @$requests, $get_requests if @$get_requests;
	local $_;

	if(@$requests)
	{
		foreach my $tasks(@$requests)
		{
			foreach my $key(@$tasks)
			{
				my $task = $key->{task};
				my $args = $key->{args};
				if(0 != index($task,"_") && $self->can($task))
				{
					try
					{
						$response->{$task.'_response'} = {response => $self->$task($args), code => 200, error => 0};
					}
					catch
					{
						my $error;
						my $mes = $_->{message};
						my ($error_code) = $mes =~ /^(\d+).*/;

						if(defined $error_code)
						{
							$error = '404' eq $error_code ? 'Not Found' : $self->_localize('ERROR_'.$error_code);
						}
						else
						{
							$error = 'Internal Server Error';
							$error_code = 500;
						}
						$response->{$task.'_response'} = {response => $error, error => 1, code => $error_code};
						$self->_dump($mes) if $debug;
					}
				}
				else
				{
					$response->{$task.'_response'} = {response => 'Not Found', error => 1, code => 404};
				}
			}
		}
	}

	return $response;
}

sub get_locale
{
	my ($self,$args) = @_;
	my $locale = {};
	foreach(@$args)
	{
		$locale->{$_} = $self->_localize($_)
	}

	return $locale;
}

sub check_access
{
	my ($self,$args) = @_;

	die "400 no arguments to check access" if(ref($args) ne "HASH" || !%$args);

	my $access = {};
	foreach my $key(keys %$args)
	{
		if(ref($args->{$key}) eq "HASH")
		{
			$access->{$key} = $self->_get_access({attr => $args->{$key}->{attr}, obj => $args->{$key}->{obj}});
		}
		else
		{
			$access->{$key} = $args->{$key};
		}
	}

	return $access;
}


###################################################################################
# cdrs

sub get_cdrs
{
	my ($self,$args) = @_;

	die "400 no arguments to get cdrs" if ref($args) ne "HASH" || !%$args;

	use Porta::CDR;
	use Porta::Date;
	use POSIX;
	use Porta::Services;

	my $ph = $self->_get('ph');
	my $info = $self->_get('info');
	my $realm = $self->_get('realm');
	my $cdr = new Porta::CDR($ph);
	my $st = new Porta::Services($ph);
	my $list_services = $st->get_types_list({
		plugin => undef,
		vendor_services => 0
	});
	my $service_names = {
		voice_calls => 'Voice Calls',
		subscriptions => 'Subscriptions',
		payments => 'Payments',
		credits => 'Credits / Adjustments',
		messaging => 'Messaging Service',
		faxes => 'Faxes',
		data_service => 'Data Service [MB]',
		quantity_based => 'Quantity Based'
	};
	my $list = {};

	foreach my $s_type (@$list_services)
	{
		my $service_name = undef;
		foreach(keys %$service_names)
		{
			if($service_names->{$_} eq $s_type->{name})
			{
				$service_name = $_;
				last;
			}
		}

		next if(!$service_name || !defined $args->{$service_name} && !defined $args->{all});

		my $_args = defined $args->{all} ? $args->{all} : $args->{$service_name};
		my $from = $_args->{from} || 0;
		my $limit = $_args->{limit} || 'all';
		my $from_date = undef;
		my $to_date = undef;

		$from_date = $self->_format_datetime("default",$_args->{from_date},$ph->{TZ}) if defined $_args->{from_date};
		$to_date = $self->_format_datetime("default",$_args->{to_date},$ph->{TZ}) if defined $_args->{to_date};
		if(!defined $from_date || !defined $to_date)
		{
			if(!defined $from_date)
			{
				my $date = Porta::Date->new();
				$date->add_interval('MONTH', '-', 1);
				$from_date = $date->asISO($ph->{TZ});
			}
			if(!defined $to_date)
			{
				my $date = Porta::Date->new();
				$date->add_interval('DAY', '+', 3);
				$to_date = $date->asISO($ph->{TZ});
			}
		}
		$limit = 200 if ('all' eq $limit || $limit > 200);
		my $hash = {
			i_env           => $ph->{'i_env'},
			i_service		=> $s_type->{i_service},
		    owner           => lc($realm),
		    i_owner         => $realm eq 'Account' ? $info->{i_account} : $info->{i_customer},
		    i_customer_type => $realm eq 'Account' ? undef : $info->{i_customer_type},
		   	from            => $from,
		    pager           => $limit,
		    from_date       => $from_date,
		    to_date         => $to_date
		};

		my $subtotal = $cdr->get_subtotal($hash);
		$list->{$service_name} = {
			list => $cdr->get_cdrs($hash),
			total_amount => $subtotal->{$s_type->{i_service}}->{charged_amount},
			total_count => $subtotal->{$s_type->{i_service}}->{total},
			from => $from,
			limit => $limit
		};
	}

	if(%$list)
	{
		foreach my $service_name(keys %$list)
		{
			my $_list = $list->{$service_name}->{list};
			$list->{$service_name}->{list} = [];
			my $subtotal_amount = 0;
			my $subtotal_count = 0;

			foreach my $cdr(@$_list)
			{
				my $row = undef;
				$subtotal_amount += $cdr->{charged_amount};
				$subtotal_count++;
				if('voice_calls' eq $service_name)
				{
					my $connect_date = $self->_format_datetime($ph->{out_date_format},$cdr->{unix_connect_time});
					my $connect_time = $self->_format_datetime($ph->{out_time_format},$cdr->{unix_connect_time});
					my $duration = floor($cdr->{charged_quantity}/60).':'.($cdr->{charged_quantity}%60 < 10 ? '0'.$cdr->{charged_quantity}%60 : $cdr->{charged_quantity}%60);
					$row = {
						connect_date => $connect_date,
						connect_time => $connect_time,
						unix_connect_time => $self->_format_datetime('unixtime',$cdr->{unix_connect_time}),
						duration => $duration,
						account_id => $cdr->{account_id},
						cli => $cdr->{cli},
						cld => $cdr->{cld},
						amount => $cdr->{charged_amount},
						description => $cdr->{description},
						country => $cdr->{country}
					};
				}
				elsif('subscriptions' eq $service_name)
				{
					$row = {
						account_id => $cdr->{account_id},
						unix_time_from => $self->_format_datetime('unixtime',$cdr->{unix_connect_time}),
						unix_time_to => $self->_format_datetime('unixtime',$cdr->{unix_disconnect_time}),
						fee_type => $cdr->{description},
						fee_name => $cdr->{cld},
						from_date => $self->_format_datetime($ph->{out_date_time_format},$cdr->{unix_connect_time}),
						to_date => $self->_format_datetime($ph->{out_date_time_format},$cdr->{unix_disconnect_time}),
						amount => $cdr->{charged_amount}
					};
				}
				elsif($self->_in_array(['payments','credits'],$service_name))
				{
					$row = {
						account_id => $cdr->{account_id},
						description => $cdr->{description},
						comment => $cdr->{cld},
						date_time => $self->_format_datetime($ph->{out_date_time_format},$cdr->{unix_connect_time}),
						unix_time => $self->_format_datetime('unixtime',$cdr->{unix_connect_time}),
						amount => $cdr->{charged_amount}
					};
				}
				elsif($self->_in_array(['data_service','quantity_based','messaging'],$service_name))
				{
					$row = {
						account_id => $cdr->{account_id},
						description => $cdr->{description},
						date_time => $self->_format_datetime($ph->{out_date_time_format},$cdr->{unix_connect_time}),
						unix_time => $self->_format_datetime('unixtime',$cdr->{unix_connect_time}),
						quantity => $cdr->{charged_quantity},
						amount => $cdr->{charged_amount},
						country => $cdr->{country}
					};
					if($self->_in_array(['quantity_based','messaging'],$service_name))
					{
						$row->{quantity} = $cdr->{charged_quantity};
					}
					elsif($service_name eq 'data_service')
					{
						$row->{quantity} = sprintf("%.2f",$cdr->{charged_quantity}/1048576);
					}
				}
				push(@{$list->{$service_name}->{list}},$row);
			}
			$list->{$service_name}->{subtotal_amount} = $subtotal_amount;
			$list->{$service_name}->{subtotal_count} = $subtotal_count;
		}
	}

	return $list;
}


###################################################################################
# info

sub get_attributes
{
	my ($self, $args) = @_;

	die "400 no arguments to get attributes" if !@$args;

	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $output = {};

	foreach my $attribute(@$args)
	{
		my $access = $self->_get_access($attribute);
		if($access && !defined $output->{$attribute})
		{
			$output->{$attribute} = {access => $access, title => $self->_localize($attribute)};
			my $options = $self->_get_options($attribute);
			if(defined $options)
			{
				my $value;
				if($access eq 'update')
				{
					$value = $options;
				}
				elsif($access eq 'read')
				{
					my $selection = $self->_get_option_name($attribute);
					$output->{$attribute}->{selection} = $selection->{value};
					$value = $selection->{name};
				}
				$output->{$attribute}->{value} = ($value || '');
			}
			else
			{
				my $value;
				my $attribute_properties = $self->_attribute_properties($attribute);
				if(defined $attribute_properties->{service})
				{
					$value = $self->_get_service($attribute);
				}
				elsif(defined $info->{$attribute})
				{
					$value = $info->{$attribute};
					if(defined $attribute_properties && defined $attribute_properties->{format})
					{
						if('price' eq $attribute_properties->{format} && $access eq 'read')
						{
							$value = $self->_format_price($info->{$attribute});
						}
						elsif($self->_in_array(['date','time','date_time'],$attribute_properties->{format}))
						{
							$value = $self->_format_datetime($ph->{'out_'.$attribute_properties->{format}.'_format'},$info->{$attribute});
						}
					}
				}
				else
				{
					$value = '';
				}
				$output->{$attribute}->{value} = $value;
			}
		}
	}

	return $output;
}

sub set_attributes
{
	my ($self,$args) = @_;
	my $options_list = $self->_get('options_list');
	my $info = $self->_get('info');
	my $hash = {};

	foreach my $key (keys %$args)
	{
		my $access = $self->_get_access($key);
		if($access && $access eq 'update')
		{
			my $value = undef;
			my $properties = $self->_attribute_properties($key);
			my $allowed_options = $self->_get_options($key);
			if(defined $allowed_options)
			{
				my $valid = 0;
				foreach my $i(@$allowed_options)
				{
					if((!$args->{$key} && !$i->{value} || $args->{$key} eq $i->{value}) && !$i->{sel})
					{
						$valid = 1;
						$value = $args->{$key} || '';
						$options_list->{$key} = undef;
						last;
					}
					elsif((!$args->{$key} && !$i->{value} || $args->{$key} eq $i->{value}) && $i->{sel})
					{
						$valid = 1;
						last;
					}
				}
				die "403 $args->{$key} not allowed for $key" if !$valid;
			}
			else
			{
				$value = $args->{$key};
			}

			if(defined $value)
			{
				if(defined $properties->{service_flag} && $info->{service_flags_hash}->{$key} ne $value)
				{
					$hash->{'srv_'.$key} = $value;
				}
				elsif(defined $properties->{service} && $properties->{service} ne 'other')
				{
					my @keys = split('->', $properties->{service});
					my $nesting = '';
					my $service_flag;
					my $old_value;
					foreach(@keys)
					{
						$service_flag = $_ if !$service_flag;
						$nesting .= '->{'.$_.'}';
					}
					eval '$old_value = $info->{services}'.$nesting.'->{value}';
					if((!defined $old_value || $old_value ne $value) && (!defined $hash->{'srv_'.$service_flag} || $hash->{'srv_'.$service_flag} ne 'N'))
					{
						$hash->{'srv_'.$key} = $value;
						$hash->{'srv_'.$service_flag} = $info->{service_flags_hash}->{$service_flag} if !defined $hash->{'srv_'.$service_flag};
					}
				}
				else
				{
					$hash->{$key} = $value;
				}
			}
		}
		else { die "403 no update access for $key"; }
	}
	if(%$hash)
	{
		my $obj = $self->_get('obj');
		my $realm = $self->_get('realm');
		if($realm eq 'Account')
		{
			$hash->{i_account} = $info->{i_account};
			$hash->{password} = $info->{password};
			$hash->{login} = $info->{login} if !defined $hash->{login};
			$obj->update($hash);
			$info = $obj->get($info->{i_account}, {get_services => 1});
		}
		else
		{
			$hash->{i_customer} = $info->{i_customer};
			$obj->update($hash);
			$info = $obj->get($info->{i_customer}, 0,  {get_services => 1});
		}
		$info->{password_lifetime} = 1;
		$self->_set("info",$info);
		$self->_set('options_list',$options_list);
	}
	return {success => $self->_localize('SUCCESS_UPDATED')};
}

sub set_pass
{
	use Litespan;

	my $self = shift;
	my $args = shift;
	my $ph = $self->_get('ph');
	my $obj = $self->_get('obj');
	my $info = $self->_get('info');
	my $realm = $self->_get('realm');

	if(ref($args) ne "HASH" || !%$args)
	{
		die "400 no arguments to set password";
	}
	elsif(!($self->_get_access({attr => "Change Password", obj => "WebForms"})) || !($self->_get_access({attr => 'password', obj => $realm."s"})))
	{
	    die "403 not allowed to change password";
	}
	elsif(!$args->{new_password} || !$args->{old_password})
	{
		die "400 not enough arguments to set password";
	}
	elsif($args->{old_password} ne $info->{password})
	{
	    die "420 incorrect old password";
	}
	elsif($args->{old_password} eq $args->{new_password})
	{
	    die "410 old password is equal to the new one";
	}
	elsif(Litespan::is_password_weak($args->{new_password}))
	{
		die "421 password is too weak";
	}
	else
	{
		use Porta::Date;

		my $update_hash = {
			password => $args->{new_password},
			password_timestamp => Porta::Date->new->asISO,
			login => $info->{login}
		};

	    $ph->get_sc()->set_session_var($ph->{session_id}, 'ch_password', 0);

        if($realm eq 'Account')
		{
			$update_hash->{i_account} = $ph->{i_account};
			$obj->update($update_hash);
			$info = $obj->get($ph->{i_account}, {get_services => 1});
		}
		else
		{
			$update_hash->{i_customer} = $ph->{i_customer};
			$obj->update($update_hash);
			$info = $obj->get($ph->{i_customer}, 0, {get_services => 1});
		}
		$info->{password_lifetime} = 1;
		$self->_set('info',$info);

		return {notice => $self->_localize('pass_changed')};
	}
}

sub get_password_expired
{
	my $self = shift;
	my $access = $self->_get_access({attr => "Change Password", obj => "WebForms"}) && $self->_get_access({attr => 'password', obj => ($self->_get('realm')."s")}) eq "update";
	my $change_pass = "N";
	if($access)
	{
		my $ph = $self->_get('ph');
		if(!$ph->{super_pwd_mode})
		{
			my $info = $self->_get("info");
			my $expiration = $ph->getConfigValue('Web', 'Password_expire');
			$change_pass = "Y" if ($expiration && (!defined $info->{password_lifetime} || $info->{password_lifetime} > $expiration));
		}
	}

	return {value => $change_pass, access => "read", name => "Password expired"};
}

sub get_subscriptions
{
	my ($self,$args) = @_;
	my $realm = $self->_get("realm");

	die "403 no permissions to access subscriptions" if(!($self->_get_access({attr => '*', obj => $realm."_Subscriptions"})));

	use Porta::Subscriptions;

	my $output = [];
	my $ph = $self->_get('ph');
	my $i_value = $realm eq 'Account' ? 'i_account' : 'i_customer';
	my @susbs_status = qw(pending active closed);
	my $SS = Porta::Subscriptions->new($ph);
	my $subs_list = $SS->getObjSubscriptionsList({obj => $realm, $i_value => $ph->{$i_value}});

	if(@$subs_list)
	{
		foreach my $key (@$subs_list)
		{
			if(!defined $args->{status} || $susbs_status[$key->{int_status}] eq $args->{status})
			{
				push(@{$output},{
					subscription => $key->{name},
					discount_rate => ($key->{discount_rate} ? $key->{discount_rate}.' %' : ''),
					start_date => $key->{start_date},
					activation_date => $key->{activation_date},
					finish_date => ($key->{finish_date} || ''),
					billed_to => ($key->{billed_to} || ''),
					status => $susbs_status[$key->{int_status}]
				});
			}
		}
	}

	return $output;
}

sub get_discount_counters
{
	my $self = shift;
	my $realm = $self->_get("realm");

	die "403 no permissions to access discounts" if (!($self->_get_access({attr => '*', obj => $realm."_Volume_Discount_Counters"})));

	use Porta::DiscountPlan;

	my $output = [];
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $DP = new Porta::DiscountPlan($ph);
	my $dest_groups = $DP->getDiscountCounters({i_vd_plan => $info->{i_vd_plan}, i_customer => $info->{i_customer}});
	my @peak_levels = $DP->peak_levels();
	my @peak_level_names = map { $self->_localize('Peak_Level'.$_) } @peak_levels;

	if(defined $dest_groups && @$dest_groups)
	{
		foreach my $row (@$dest_groups)
		{
			foreach my $peak_level (@peak_levels)
			{
				if(!$row->{scheme_for}->{$peak_level}) { next; }
				my $peak = undef;
				my $discounts = {};
				my $unit = ($row->{threshold_type} eq 'Charged Amount') ? $info->{iso_4217} : $row->{service_rate_unit};
				my $counter = $row->{scheme_for}->{$peak_level}->{counter};

				if ($row->{scheme_for}->{$peak_level}->{max_peak_level} > $peak_levels[-1])
				{
					$row->{scheme_for}->{$peak_level}->{max_peak_level} = $peak_levels[-1];
				}

				if ($peak_level == 0 && $row->{scheme_for}->{$peak_level}->{max_peak_level} >= $peak_levels[-1])
				{
					$peak = 'N/A';
				}
				else
				{
					$peak =  join(', ', @peak_level_names[$peak_level..$row->{scheme_for}->{$peak_level}->{max_peak_level}]);
				}

				foreach my $prefix (("", "next_"))
				{
					my $key = ($prefix eq '') ? 'current' : $prefix;
					my $discount = $counter->{$prefix . 'discount'};
					my $blocked  = $counter->{$prefix . 'blocked'};
					my $limited  = $counter->{$prefix . 'limited'};
					$discounts->{$key} = $blocked ? 'Service_Blocked' : ((!defined $discount) ? 'N/A' : $discount . '%' . ($discount == 0 ? ' (normal rate)' : ($discount == 100 ? ' (for free)' : '')).( $limited ? ', Limited Usage' : ''));
				}

				push(@{$output},{
					dg_name => $row->{dg_name},
					service_name => $row->{service_name},
					peak_level => $peak,
					threshold => ($counter->{threshold} ? $counter->{threshold}.' '.$unit : 'N/A'),
					used => ($counter->{value} || 0).' '.$unit,
					remaining => ($counter->{rest} || 0).' '.$unit,
					current_discount => $discounts->{current},
					next_discount => $discounts->{next_},
				});
			}
		}
	}

	return $output;
}

sub get_custom_fields
{
	use Porta::CustomFields;

	my $self = shift;
	my $p = shift || {};
	my $ph = $self->_get('ph');
	my $realm = $self->_get('realm');
	my $output = {};
	$p->{i_account} = defined $p->{i_account} && 'Account' ne $realm ? $p->{i_account} : $ph->{i_account};
	$p->{i_customer} = 'Account' eq $realm ? undef : $ph->{i_customer};
	$p->{fields} = defined $p->{fields} && ref($p->{fields}) eq "ARRAY" ? $p->{fields} : [];

	my $obj = new Porta::CustomFields($ph);
	my $custom_fields = $obj->get_custom_fields({
		i_env => $ph->{i_env},
		object => ('Account' eq $realm ? 'account' : 'customer'),
		i_account => $p->{i_account},
		i_customer => $p->{i_customer},
	});
	my $forbidden_fields = [];

	foreach my $field(@$custom_fields)
	{
		next if(@{$p->{fields}} && !$self->_in_array($p->{fields},$field->{name}));
		my $access = $self->_get_access({attr => 'custom_field'.$field->{i_custom_field}, obj => $realm.'_Custom_Fields'});
		if($access)
		{
			my $value;
			if(defined $field->{select_list})
			{
				foreach($field->{select_list})
				{
					if("update" eq $access)
					{
						$value = [{name => $self->_localize('none'), value => "", sel => ($_->{value} eq $field->{value} ? 1 : 0)}] if !$value;
						push @$value,{name => $_->{text}, value => $_->{value}, sel => ($_->{value} eq $field->{value} ? 1 : 0)};
					}
					elsif($_->{value} eq $field->{value})
					{
						$value = $field->{value};
						last;
					}
				}
			}
			$value = $value ? $value : $field->{value};
			$output->{$field->{name}} = {title => $field->{name}, value => $value, access => $access, i_custom_field_value => $field->{i_custom_field_value}};
		}
		else{ push @$forbidden_fields, $field;}
	}

	my $forbidden_fields_length = scalar grep { defined $_ } @$forbidden_fields;
	if($forbidden_fields_length)
	{
		my $fields_length = @{$p->{fields}} ? scalar grep { defined $_ } @{$p->{fields}} : scalar grep { defined $_ } @$custom_fields;
		die "403 no permissions to access custom fields" if($forbidden_fields_length == $fields_length);
	}

	return $output;
}

sub set_custom_fields
{
	my ($self,$args) = @_;

	die "400 no arguments to update custom fields" if ref($args) ne "HASH" || !%$args;

	my $custom_fields = $self->get_custom_fields();

	die "403 no permissions to access custom fields" if !%$custom_fields;

	my $update = [];
	my $ph = $self->_get('ph');
	my $realm = $self->_get('realm');
	foreach my $key(keys %$args)
	{
		if(defined $custom_fields->{$key})
		{
			die "403 no update access for $key" if "update" ne $custom_fields->{$key}->{access};

			push @$update, {
				value => $args->{$key},
				i_custom_field_value => $custom_fields->{$key}->{i_custom_field_value},
				object => ('Account' eq $realm ? 'account' : 'customer'),
				i_account => ('Account' eq $realm ? $ph->{i_account} : undef),
				i_customer => ('Account' eq $realm ? undef : $ph->{i_customer}),
			}
		}
	}

	if(@$update)
	{
		use Porta::CustomFields;

		my $obj = new Porta::CustomFields($ph);
		foreach(@$update)
		{
			$obj->update_cf_value($_);
		}
	}

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

###################################################################################
# payment

sub get_payment_info
{
	use Porta::Payment;
	use PayGW::PayPal;
	use Porta::Env;
	use Porta::Customer;

	my $self = shift;
	my $output = {};
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $realm = $self->_get('realm');
	my $payment = new Porta::Payment($ph);
	my $cc_info = $info->{i_credit_card} ? $payment->card_info($info->{i_credit_card}) : undef;
	my $processor = undef;

	if(defined $cc_info && ref($cc_info) eq "HASH" && %$cc_info)
	{
		my $payment_methods = $self->_get_options('i_payment_method');
		$output->{use_cc} = {value => "", access => 'read', title => $self->_localize('use')};
		foreach my $method (@$payment_methods)
		{
			if(defined ($cc_info->{i_payment_method}) && $cc_info->{i_payment_method} eq $method->{value})
			{
				$output->{use_cc}->{value} .= $method->{name};
				last;
			}
		}
		$output->{use_cc}->{value} .= $cc_info->{number} ? " ".$cc_info->{number} : "";
	}

	my $cust = new Porta::Customer($ph);
	my $cust_info = $cust->get($info->{i_customer});
	my $e = new Porta::Env($ph);
	my $provider_info = $cust_info->{i_parent} ? $cust->get($cust_info->{i_parent}) : $e->get( { i_env => $ph->{i_env} } );
	utf8::decode($provider_info->{companyname});
	$provider_info->{lname} ||= $provider_info->{companyname};
	$output->{pay_to} = {value => $provider_info->{lname}, access => 'read', title => $self->_localize('pay_to')};
	if(defined $cc_info && ref($cc_info) eq "HASH" && %$cc_info)
	{
		$processor = $payment->findProcessor({
			card       => $cc_info,
			i_customer => ($realm ne 'Account' ? $ph->{i_customer} : undef),
			i_account  => ($realm eq 'Account' ? $ph->{i_account} : undef)
		});
	}
	$output->{cc_payment} = {
		value => ((defined $cc_info && ref($cc_info) eq "HASH" && $cc_info->{i_payment_method} && $processor && $processor->{ext_auth} eq 'N') ? "Y" : "N"),
		title => $self->_localize("make_payment"),
		access => "read"
	};

	my $obj = $self->_get('obj');
	my $i_customer = $realm eq 'Account' ? $info->{i_account} : $info->{i_customer};
	my $env = $e->get( { i_env => $ph->{i_env} } );
	my $pgw = PayGW::PayPal->new();
	$pgw->init(1);
	my $method = $realm eq "Account" ? "isConfiguredForAccount" : "isConfiguredForCustomer";
	$output->{paypal_payment} = {value => ($pgw->$method($i_customer,$env->{name}) ? "Y" : "N"), title => "PayPal", access => "read"};
	$output->{voucher_payment} = {value => $realm eq 'Account' ? "Y" : "N", title => $self->_localize("voucher_topup"), access => "read"};
	$output->{ppayments} = {value => ($output->{cc_payment}->{value} eq "Y" && $info->{ecommerce_enabled} eq "Y" ? "Y" : "N"), title => $self->_localize("ppayments"), access => "read"};

	return $output;
}

sub get_credit_card
{
	use Porta::Payment;

	my $self = shift;
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $payment = Porta::Payment->new($ph);
	my $cc_info = $info->{i_credit_card} ? $payment->card_info($info->{i_credit_card}) : {};
	my $cc_fields = ['i_payment_method','number','exp_date','cvv','name','address','city','iso_3166_1_a2','i_country_subdivision','zip'];
	my $output = {};

	foreach my $key(@$cc_fields)
	{
		my $name = 'cc_'.$key;
		my $access = $self->_get_access($name);
		if($access)
		{
			$output->{$name} = {access => $access, title => $self->_localize($name)};
			if($self->_in_array(['iso_3166_1_a2','i_payment_method'],$key))
			{
				my $options = $self->_get_options($key);

				die "403 no suitable payment processor" if ($key eq "i_payment_method" && (ref($options) ne "ARRAY" || (scalar grep { defined $_ } @$options) < 2));

				my $value;
				if($access eq 'update')
				{
					$value = $options;
				}
				else
				{
					foreach my $option(@$options)
					{
						if($option->{sel})
						{
							$value = $option->{name};
							last;
						}
					}
				}
				$output->{$name}->{value} = $value;
			}
			elsif($key eq 'i_country_subdivision')
			{
				my $options = $self->_get_options($key);
				my $value;
				if($access eq 'update')
				{
					$value = $options;
				}
				elsif(defined $cc_info->{iso_3166_1_a2})
				{
					foreach(@{$options->{$cc_info->{iso_3166_1_a2}}})
					{
						if($_->{sel})
						{
							$value = $_->{name};
							last;
						}
					}
				}
				$output->{$name}->{value} = $value;
			}
			else
			{
				$output->{$name}->{value} = $cc_info->{$key};
			}
		}
	}

	die "403 no permissions to access credit card" if !%$output;

	return $output;
}

sub get_ppayments
{
	my $self = shift;

	die "403 no permissions to access ppayments" if(!$self->_get_access({attr => '*', obj => 'Periodical_Payments'}));

	my $payment_info = $self->get_payment_info();

	die "403 no permissions to access ppayments" if(!$payment_info->{ppayments}->{access} || $payment_info->{ppayments}->{value} ne "Y");

	use Porta::Payment;
	use Porta::Date;

	my $p = shift;
	$p->{limit} = defined $p->{limit} && $p->{limit} < 30 && $p->{limit} > 1 ? $p->{limit} : 30;
	$p->{from} = defined $p->{from} ? $p->{from} : 0;
	$p->{filter} = defined $p->{filter} && $self->_in_array(["All","Now","beforeNow","afterNow"],$p->{filter}) ? $p->{filter} : "Now";
	my $output = {};
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $realm = $self->_get('realm');
	my $payment = new Porta::Payment($ph);
	my $today = new Porta::Date;

	my $processor = $payment->findProcessor({
		i_account  => $realm eq 'Account' ? $ph->{i_account} : undef,
		i_customer => $realm eq 'Account' ? undef : $ph->{i_customer},
		card => {i_payment_method => $info->{i_payment_method}}
	});

	my $frequency = $payment->get_payments_frequency();
	foreach (@$frequency) { $_->{name} = $self->_localize($_->{name}); }
	my $pp_allowed = 0;
	if (defined $processor &&  $processor->{reccuring_enabled} eq 'Y')
	{
		if ( $realm eq 'Account' ) { $pp_allowed = 1 if $info->{ecommerce_enabled} eq 'Y'; }
		else { $pp_allowed = 1; }
	};

	die "403 no permissions to access ppayments" if !$pp_allowed;

    my $list = undef;
    my $total = undef;
    ($list,$total) = $payment->getlist_ppayments({
        i_object => ($realm eq 'Account' ? $ph->{i_account} : $ph->{i_customer}),
		object => lc($realm),
        filter => $p->{filter},
        from => $p->{from},
        pager => $p->{limit}-1
	});
	$output = {
		from => $p->{from},
		limit => $p->{limit},
		total_count => $total,
		subtotal_count => 0,
		filter => $p->{filter},
		list => []
	};
	if(@$list)
	{
		foreach my $key (@$list)
		{
			my $access = $key->{editable} ? 'update' : 'read';
			my $_frequency;
			if('update' eq $access)
			{
				foreach my $k(@$frequency)
				{
					push(@$_frequency,{
						name => $k->{description},
						value => $k->{value},
						sel => ($key->{i_ppp} == $k->{value} ? 1 : 0)
					});
				}
			}
			else { $_frequency = $key->{period}; }

			push(@{$output->{list}},{
				i_ppayment => $key->{i_ppayment},
				accepted => $key->{accepted},
				amount => $key->{amount} ? sprintf("%.2f", $key->{amount}) : 0,
				i_periodical_payment_period => $_frequency,
				balance_threshold => defined $key->{threshold} ? sprintf("%.2f", $key->{threshold}) : 0,
				from_date => $key->{from_date},
				to_date => $key->{to_date},
				number_payments => $key->{number_payments},
				frozen => $key->{frozen},
				discontinued => $key->{discontinued},
				editable => $key->{editable}
			});
			++$output->{subtotal_count};
		}
	}

	return $output;
}

sub set_credit_card
{
	use Porta::Payment;
	my ($self, $args) = @_;

	die "400 no arguments to update credit card" if(ref($args) ne "HASH" || !%$args);

	my $info = $self->_get('info');
	my $realm = $self->_get('realm');
	my $ph = $self->_get('ph');
	my $obj = $self->_get('obj');
	my $options_list = $self->_get('options_list');
	my $payment = new Porta::Payment($ph);
	my @cc_fields = qw(i_payment_method number exp_date cvv name address city iso_3166_1_a2 i_country_subdivision zip);
	my $cc_info = {
		i_credit_card => $info->{i_credit_card},
		i_env         => $ph->{i_env},
		parent_table  => $realm.'s',
		parent_key    => ($realm eq 'Account' ? $ph->{i_account} : $ph->{i_customer})
	};
	foreach my $key (@cc_fields)
	{
		my $name = 'cc_'.$key;
		my $access = $self->_get_access($name);
		if(defined($args->{$name}) && $access eq 'update')
		{
			my $allowed_options = $self->_get_options($key);
			if(defined $allowed_options)
			{
				$allowed_options = $allowed_options->{$args->{cc_iso_3166_1_a2}} if ($key eq 'i_country_subdivision' && defined $args->{cc_iso_3166_1_a2} && $args->{cc_iso_3166_1_a2});
				my $valid = 0;
				foreach my $i(@$allowed_options)
				{
					if($args->{$name} eq $i->{value} && !$i->{sel})
					{
						$valid = 1;
						$options_list->{$key} = undef;
						$cc_info->{$key} = $args->{$name};
						last;
					}
					elsif($args->{$name} eq $i->{value} && $i->{sel})
					{
						$valid = 1;
						last;
					}

				}
				die "403 $args->{$name} is not allowed for $key" if !$valid;
			}
			else
			{
				$cc_info->{$key} = $args->{$name};
			}
		}
		elsif(defined($args->{$name}) && $access ne 'update')
		{
			die "403 no update access for $key";
		}
	}

	my $i_credit_card = $payment->update_card($cc_info);

	if($i_credit_card && !$cc_info->{i_credit_card})
	{
		my $obj = $self->_get('obj');
		my $hash;
		if($realm eq 'Account')
		{
			$hash = {
				i_subscriber => $info->{i_subscriber},
				i_credit_card => $i_credit_card
			};
			$obj->updateSubscriber($hash , $ph->{i_account});
			$info = $obj->get($ph->{i_account}, {get_services => 1});
		}
		else
		{
			$hash = {
				i_customer => $ph->{i_customer},
				i_credit_card => $i_credit_card
			};
			$obj->update($hash);
			$info = $obj->get($ph->{i_customer}, 0,  {get_services => 1});
		}
		$info->{password_lifetime} = 1;
		$self->_set("info",$info);
		$self->_set('options_list',$options_list);
	}

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

sub set_paypal_payment
{
	my ($self, $args) = @_;

	die "400 no arguments for PayPal" if(ref($args) ne "HASH" || !%$args);

	use PayGW::PayPal;
	use Porta::Env;

	my $amount = abs($args->{amount});
	my $return_page = $args->{return_page};
	my $cancel_page = $args->{cancel_page};

	die "400 incorrect arguments for PayPal" if(!$amount || $amount < 1 || !$return_page || !$cancel_page);

	my $ph = $self->_get('ph');
	my $obj = $self->_get('obj');
	my $info = $self->_get('info');
	my $realm = $self->_get('realm');
	my $e = new Porta::Env($ph);
	my $i_customer = $realm eq 'Account' ? $info->{i_account} : $info->{i_customer};
	my $env = $e->get( { i_env => $ph->{i_env} } );
	my $method = $realm eq "Account" ? "isConfiguredForAccount" : "isConfiguredForCustomer";
	my $pgw = PayGW::PayPal->new();
	$pgw->init(1);

	die "403 PayPal is not configured" if(!($pgw->$method($i_customer,$env->{name})));

	if($pgw->getPayPalFixedMCFeePC())
	{
		$amount = $amount + $amount*$pgw->getPayPalFixedMCFeePC()/100;
	}
	$amount = $ph->round_up($amount, 2);

	my ($return_page_uri,$return_page_params) = $return_page =~ /^(.+)(\?.+)$/;
	$return_page = $return_page_uri if $return_page_uri;
	my ($cancel_page_uri,$cancel_page_params) = $cancel_page =~ /^(.+)(\?.+)$/;
	$cancel_page = $cancel_page_uri if $cancel_page_uri;

	my $button = $pgw->makeButton({
		amount			=> $amount,
		i_account		=> ($realm eq 'Account' ? $ph->{i_account} : undef),
		i_customer		=> ($realm eq 'Account' ? undef : $info->{i_customer}),
		currency_code	=> $info->{iso_4217},
		i_env			=> $ph->{i_env},
		customer_name	=> ($realm eq 'Account' ? undef : $info->{name}),
		accountid		=> ($realm eq 'Account' ? $pgw->getAccountID($ph->{i_account}) : undef),
		return_page		=> $return_page,
    	cancel_page		=> $cancel_page,
    	web_path		=> ($realm eq 'Account' ? 'https://mybilling.telinta.com/accounts' : 'https://mybilling.telinta.com/customer_selfcare'),
		env_name		=> $env->{name}
	});

	my $replacements = [];
	push @$replacements, {
		needle => 'name="cancel_return" value="'.$cancel_page.'\?sessionid=\w+"',
		replacement => 'name="cancel_return" value="'.$cancel_page.($cancel_page_params ? $cancel_page_params : "").'"'
	};
	push @$replacements, {
		needle => 'name="return" value="'.$return_page.'\?sessionid=\w+"',
		replacement => 'name="return" value="'.$return_page.($return_page_params ? $return_page_params : "").'"'
	};
	foreach(@$replacements) { $button =~ s/$_->{needle}/$_->{replacement}/; }

	return $button;
}

sub set_payment
{
	my ($self, $args) = @_;

	die "400 no arguments to provide payment" if(ref($args) ne "HASH" || !%$args);

	use Porta::Payment;

	my $ph = $self->_get('ph');
	my $info = $self->_get('info');
	my $realm = $self->_get('realm');
	my $amount = $args->{amount};
	my $alternate = $args->{alternate} || undef;
	my $output = {};
	my $card_info;

	die "403 amount is too small for payment" if (!$amount || $amount < 1);

	my $payment = new Porta::Payment($ph);
	if(!$alternate)
	{
		die "403 no credit card" if(!$info->{i_credit_card});
		$card_info = $payment->card_info($info->{i_credit_card});
		$card_info->{number} = $payment->restore_card_number( $info->{i_credit_card} );
	}
	else
	{
	    my @cc_fields = qw(i_payment_method number exp_date cvv name address city iso_3166_1_a2 i_country_subdivision zip);
	    $card_info = {i_env	=> $ph->{i_env}, i_credit_card	=> 'Card_Is_Not_Registered'};
		foreach my $key(@cc_fields)
		{
			my $name = 'cc_'.$key;
			if(defined($args->{$name}))
			{
				my $allowed_options = $self->_get_options($key);
				if(defined $allowed_options)
				{
					$allowed_options = $allowed_options->{$args->{cc_iso_3166_1_a2}} if $key eq 'i_country_subdivision';
					my $valid = 0;
					foreach my $i(@$allowed_options)
					{
						if($args->{$name} eq $i->{value})
						{
							$valid = 1;
							$card_info->{$key} = $args->{$name};
							last;
						}
					}
					die "403 $args->{$name} not allowed for $key" if !$valid;
				}
				else
				{
					$card_info->{$key} = $args->{$name};
				}
			}
		}
	}
	my $processor = $payment->findProcessor({
		card       => $card_info,
		i_customer => ( $realm ne 'Account' ? $ph->{i_customer} : undef ),
		i_account  => ( $realm eq 'Account' ? $ph->{i_account} : undef )
	});

	die "602 no payment processor" if(!defined $processor);
	die "603 payment processor is not supported" if($processor->{ext_auth} eq 'Y');

	my $tx = $payment->doPayment({
		card_info   => $card_info,
		i_customer	=> ( $realm ne 'Account' ? $ph->{i_customer} : $info->{i_customer} ),
		i_account	=> ( $realm eq 'Account' ? $ph->{i_account} : undef ),
		amount      => $amount,
		description => 'OnlinePayment',
	});

	die "601 payment has failed" if (!$tx || $payment->{errcode});

	$self->_set('info',("Account" eq $realm ? $obj->get($ph->{i_account}, {get_services => 1}) : $obj->get($ph->{i_customer}, 0,  {get_services => 1})));
	my $info = $self->_get('info');
	my $new_balance = abs(("Account" eq $realm && "Debit" eq $info->{bm_name} ? $info->{balance} : ($info->{credit_limit} ? $info->{credit_limit} : 0) - $info->{balance}));
	my $p = {amount => $self->_format_price($amount), new_balance => $self->_format_price($new_balance)};
	$output->{success} = $self->_localize({msg => 'voucher_recharged',p => $p}).'<br/>'.$self->_localize('transaction_id').': '.$payment->{transaction_id};

    return $output;
}

sub set_ppayment
{
	my ($self, $args) = @_;

	die "400 incorrect arguments to update ppayment" if(ref($args) ne "HASH" || !%$args || !$args->{action} || !$self->_in_array(["add","update","delete"],$args->{action}));
	die "403 no access to update ppayments" if(!$self->_get_access({attr => '*', obj => 'Periodical_Payments'}));

	my $payment_info = $self->get_payment_info();

	die "403 no access to update ppayments" if(!$payment_info->{ppayments}->{access} || $payment_info->{ppayments}->{value} ne "Y");

	use Porta::Payment;
	use Porta::Date;

	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $realm = $self->_get('realm');
	my $action = $args->{action};
	my $p = new Porta::Payment($ph);
	my $processor = $p->findProcessor({
		i_account  => $realm eq 'Account' ? $ph->{i_account} : undef,
		i_customer => $realm eq 'Account' ? undef : $ph->{i_customer},
		card => { i_payment_method => $info->{i_payment_method} }
	});

	my $min_payment = $processor->{min_allowed_payment} if defined($processor);

	my $pp_allowed = 0;
	if (defined $processor &&  $processor->{reccuring_enabled} eq 'Y')
	{
		if ($realm eq 'Account')
		{
			$pp_allowed = 1 if $info->{ecommerce_enabled} eq 'Y';
		}
		else
		{
			$pp_allowed = 1;
		}
	};

	die "403 no access to update ppayments" if !$pp_allowed;

	my $payment = defined ($args->{i_ppayment}) && $args->{i_ppayment} > 0 ? $p->get_ppayment($args->{i_ppayment}) : undef;

	if($action eq 'delete' && $payment)
	{
		die "403 no access to remove ppayment" if !$payment->{removable};
		$p->del_ppayment({
			i_periodical_payment	=> $args->{i_ppayment},
			parent_table			=> $realm.'s',
			parent_key				=> ('Account' eq $realm ? $ph->{i_account} : $ph->{i_customer})
		});
	}
	elsif($action eq 'delete') { die "403 ppayment does not exist"; }

	my @pp_fields = qw(i_periodical_payment_period amount balance_threshold from_date to_date discontinued frozen);

	foreach my $key (@pp_fields)
	{
		my $access = $self->_get_access({attr => $key, obj => 'Periodical_Payments'});
		die "403 no update access for $key" if(defined($args->{$key}) && !($access eq 'update'));
	}

	die "400 icorrect arguments to update ppayment" if(!$args->{from_date} || !$args->{to_date} || !defined $args->{amount} || "1" eq $args->{i_periodical_payment_period} && !defined $args->{balance_threshold} || "update" eq $action && !$payment);
	die "403 ppayment is not editable" if ("update" eq $action && !$payment->{editable});

	my $hash = {
		i_periodical_payment => $args->{i_ppayment} || undef,
		i_object => ('Account' eq $realm ? $ph->{i_account} : $ph->{i_customer}),
		i_env => $ph->{i_env},
		object => lc($realm),
		parent_table => $realm.'s',
		parent_key => ('Account' eq $realm ? $ph->{i_account} : $ph->{i_customer}),
		i_periodical_payment_period => $args->{i_periodical_payment_period},
		amount => $args->{amount} eq 'Pay balance' ? 0 : $args->{amount},
		balance_threshold => $args->{balance_threshold} || undef,
		from_date => $args->{from_date},
		to_date => $args->{to_date},
		discontinued => (defined $args->{discontinued} && $self->_in_array(["Y","N"],$args->{discontinued}) ? $args->{discontinued} : 'N'),
		frozen => (defined $args->{frozen} && $self->_in_array(["Y","N"],$args->{frozen}) ? $args->{frozen} : 'N')
	};

	die "604 amount is too small" if defined $min_payment && $hash->{amount} && $hash->{amount} < $min_payment;

	my $updated = 0;
	if($payment)
	{
		foreach my $k(keys %$hash)
		{
			if(defined ($payment->{$k}) && (!defined $hash->{$k} || $payment->{$k} ne $hash->{$k}))
			{
				$updated = 1;
				last;
			}
		}
	}
	else { $updated = 1; }

	return {success => $self->_localize('SUCCESS_UPDATED')} if !$updated && $action eq 'update';

	my %porta_date;
	foreach my $date_field (qw{from_date to_date})
	{
		$hash->{$date_field} = $self->_format_datetime($ph->{in_date_format},$hash->{$date_field});
		if(!Porta::Date->checkFormat($ph->{in_date_format}, $hash->{$date_field}))
		{
			die "608 incorrect date format for $date_field";
		}
		elsif(!Porta::Date->validateDate($ph->{in_date_format}, $hash->{$date_field}))
		{
			die "609 invalid date for $date_field";
		}
		$porta_date{$date_field} = Porta::Date->new({
			-date          => $hash->{$date_field},
			-format        => 'custom',
			-custom_format => $ph->{in_date_format},
		});
	}

	die "610 from_date is older that to_date" if ($porta_date{from_date}->asUnixtime() > $porta_date{to_date}->asUnixtime());

	if($payment)
	{
		if(!$payment->{removable})
		{
			if($hash->{discontinued} eq "N" && $payment->{last_payment})
			{
				my $payment_i_ppayment = $p->update_ppayment({
					i_periodical_payment => $hash->{i_periodical_payment},
					discontinued => "Y"
				});
				$hash->{last_payment} = $payment->{last_payment};
				delete $hash->{i_periodical_payment};
			}
		}
		elsif($hash->{discontinued} eq "Y")
		{
			$p->del_ppayment({
				i_periodical_payment	=> $hash->{i_periodical_payment},
				parent_table			=> $hash->{parent_table},
				parent_key				=> $hash->{parent_key}
			});
			return {success => $self->_localize('SUCCESS_UPDATED')};
		}
	}
	$p->update_ppayment($hash);

	return {success => $self->_localize('SUCCESS_UPDATED')};
}

1;