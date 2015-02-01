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
		sip_status			=> $p->{sip_status} || 'ANY',
		hide_closed_mode	=> $p->{hide_closed_mode} || 1,
		real_accounts_mode	=> $p->{real_accounts_mode} || 0,
	});
	my $output = {limit => $p->{limit}, from => $p->{from}, total => $accounts_info->{total_number}, list => []};

	if(@{$accounts_info->{numbers_list}})
	{
		foreach my $account (@{$accounts_info->{numbers_list}})
		{
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


###################################################################################
# deprecated

#sub get_dashboard
#{
#	use Porta::Account;
#	use Porta::CDR;
#	use Porta::Date;
#	use Porta::Invoice;
#	use Porta::SQL;
#	use POSIX;
#
#	my $self = shift;
#	my %output;
#	my $info = $self->_get('info');
#	my $obj = $self->_get('obj');
#	my $ph = $self->_get('ph');
#	my $realm = $self->_get('realm');
#	my @subscriber_info_layout = qw(firstname lastname address email);
#	my @service_flags_layout = qw(call_parking clir call_recording group_pickup paging);
#	my @invoice_info_layout = qw(due_date amount_due invoice_status_desc);
#	my @accounts_list_layout = qw(um_enabled model balance id);
#	my @cdr_list_layout = qw(account_id cli cld charged_amount);
#
#	$output{subscriber_info} = {title => $self->_localize('subscriber'), values => {}};
#	foreach my $key (@subscriber_info_layout)
#	{
#		$output{subscriber_info}->{values}->{$key} = {value => $info->{$key},title => $self->_localize($key)};
#	}
#
#	$output{service_flags} = {title => $self->_localize('features'), values => {}};
#
#	my $service_flags = { %{$info->{service_flags_hash}} };
#	foreach my $key (@service_flags_layout)
#	{
#		$output{service_flags}->{values}->{$key} = {value => $service_flags->{$key},title => $self->_localize($key)};
#	}
#
#	my $inv = new Porta::Invoice($ph);
#	my ($i_invoice) = Porta::SQL->fetch('GetMaxInvoiceIdCustomer', 'porta-billing-master',{ i_env => $ph->{i_env}, i_customer => $info->{i_customer} });
#	$i_invoice ||= 0;
#	my $invoice_info = {};
#	$invoice_info = $inv-> get({ i_invoice => $i_invoice, }) if $i_invoice;
#
#	if($invoice_info)
#	{
#		$output{invoice_info} = {title => $self->_localize('invoice'), values => {}};
#		foreach my $key (@invoice_info_layout)
#		{
#			my $val;
#			if($key eq 'amount_due')
#			{
#				$val = $self->_format_price($invoice_info->{$key});
#			}
#			elsif($key eq 'due_date')
#			{
#				$val = $self->_format_datetime('out_date_format',$invoice_info->{$key});
#			}
#			else
#			{
#				$val = $invoice_info->{$key};
#			}
#			$output{invoice_info}->{values}->{$key} = {value => $val,title => $self->_localize($key)};
#		}
#	}
#
#	my $limit = 5;
#	my $ac = new Porta::Account($ph);
#	my $accounts_info = $ac->getlist({i_customer          => $info->{i_customer},
#	                                  from                => 0,
#	                                  limit               => $limit,
#	                                  sip_status          => 'ANY',
#	                                  hide_closed_mode   => 1,
#	                                  real_accounts_mode => 1,
#	                                 });
#
#	if(@{$accounts_info->{numbers_list}})
#	{
#		$output{numbers_list} = {title => $self->_localize('phone_lines'), table => {}};
#		$output{numbers_list}->{table}->{thead}->{sip_status} = $self->_localize('sip');
#		$output{numbers_list}->{table}->{thead}->{status} = $self->_localize('status');
#		foreach my $key (@{$accounts_info->{numbers_list}})
#		{
#			my $account = {};
#			foreach my $k (@accounts_list_layout)
#			{
#				if(!defined $output{numbers_list}->{table}->{thead}->{$k})
#				{
#					$output{numbers_list}->{table}->{thead}->{$k} = $self->_localize($k);
#				}
#
#				my $val;
#				my $properties = $self->_attribute_properties($k);
#				if(defined($properties->{format}))
#				{
#					if($properties->{format} eq 'price')
#					{
#						$val = $self->_format_price($key->{$k});
#					}
#					elsif($properties->{format} =~ /\_time\_/ || $properties->{format} =~ /\_date\_/)
#					{
#						$val = $self->_format_datetime($properties->{format},$key->{$k});
#					}
#				}
#				else
#				{
#					$val = $key->{$k};
#				}
#				$account->{$k} = $val;
#			}
#	    	my $sip_status = $ac->getSIPinfo($key->{id});
#	    	$account->{status} = $self->_get_account_status($key);
#			$account->{sip_status} = $sip_status ? 'on' : 'off';
#			push(@{$output{numbers_list}->{table}->{tbody}},$account);
#		}
#	}
#
#	my $cdr = new Porta::CDR($ph);
#	my $cdr_limit = 10;
#	my $from_date = Porta::Date->new();
#	my $to_date = $from_date->clone();
#	   $to_date->add_interval('DAY', '+', 3);
#	   $from_date->add_interval('MONTH', '-', 1);
#	my $cdr_list = $cdr->get_cdrs({owner           => 'customer',
#	                               i_owner         => $info->{i_customer},
#	                               i_customer_type => $info->{i_customer_type},
#	                               from            => 0,
#	                               pager           => $cdr_limit,
#	                               i_service_type  => 3, # only Voice Calls
#	                               from_date       => $from_date->asISO(),
#	                               to_date         => $to_date->asISO(),
#	                              });
#	if(@$cdr_list)
#	{
#		$output{cdr_list} = {title => $self->_localize('recent_calls'), table => {}};
#		$output{cdr_list}->{table}->{thead}->{connect_time} = $self->_localize('time');
#		$output{cdr_list}->{table}->{thead}->{duration} = $self->_localize('duration');
#		$output{cdr_list}->{table}->{thead}->{connect_date} = $self->_localize('date');
#		foreach my $key (@$cdr_list)
#		{
#			my $connect_date = $self->_format_datetime('out_date_format',$key->{unix_connect_time});
#			my $connect_time = $self->_format_datetime('out_time_format',$key->{unix_connect_time});
#			my $seconds = $key->{unix_disconnect_time} - $key->{unix_connect_time};
#			my $duration = floor($seconds/60).':'.($seconds%60 < 10 ? '0'.$seconds%60 : $seconds%60);
#			my $cdr = {
#				connect_date => $connect_date,
#				connect_time => $connect_time,
#				duration => $duration
#			};
#			foreach my $k (@cdr_list_layout)
#			{
#				if(!defined $output{cdr_list}->{table}->{thead}->{$k})
#				{
#					$output{cdr_list}->{table}->{thead}->{$k} = $self->_localize($k);
#				}
#				$cdr->{$k} = 'charged_amount' eq $k ? $self->_format_price($key->{$k}) : $key->{$k};
#			}
#			$output{cdr_list}->{table}->{tbody} = [] if !defined $output{cdr_list}->{table}->{tbody};
#			push(@{$output{cdr_list}->{table}->{tbody}},$cdr);
#		}
#	}
#
#	return \%output;
#}

#sub get_info
#{
#	my $self = shift;
#	if (!($self->_get_access({attr => 'Customer Self Info', obj => 'WebForms'})))
#	{
#		die '403';
#	}
#
#	use Porta::Env;
#
#	my $info = $self->_get('info');
#	my $ph = $self->_get('ph');
#	my $obj = $self->_get('obj');
#	my %output;
#	my $e = new Porta::Env;
#	my $params = {
#		additional_info	=> ['discount_rate','tax_id','i_vd_plan','i_billing_period','send_invoices','send_statistics','i_do_batch',
#							'i_rep','i_distributor','i_template','i_number_scope','shifted_billing_date'],
#		address_info	=> ['companyname','salutation','firstname','midinit','lastname','address',
#							'state','zip','city','country','cont1','phone1','faxnum','phone2','cont2','email'],
#		user_interface	=> ['login','i_time_zone','i_lang','out_date_format','out_time_format','out_date_time_format',
#							'in_date_format','in_time_format','ppm_enabled','drm_enabled','password']
#	};
#
#	my $customer_parent = ($info->{i_customer_type} == 1) ? $info->{i_parent} : undef;
#	my $provider_info = $customer_parent ? $obj->get($customer_parent) : $e->get( { i_env => $ph->{i_env} } );
#
#	utf8::decode($provider_info->{companyname});
#	$info->{provider_info_lname} = $provider_info->{lname} || $provider_info->{companyname};
#	$self->_set('info',$info);
#
#	foreach my $key(keys %$params)
#	{
#		foreach my $k(@{$params->{$key}})
#		{
#			my $attribute = $self->_get_attribute($k);
#			if($attribute)
#			{
#				$output{$key} = {attributes => {}} if !defined $output{$key};
#				$output{$key}->{attributes}->{$k} = $attribute;
#			}
#		}
#		$output{$key}->{title} = $self->_localize($key) if defined $output{$key};
#	}
#
#	if(defined $output{user_interface}->{attributes}->{password})
#	{
#		my $hidden_pass = '';
#		while(length($hidden_pass) < length($info->{password}))
#		{
#			$hidden_pass .= '*';
#		}
#		$output{user_interface}->{attributes}->{password} = {
#			title => $self->_localize('password'),
#			value => $hidden_pass,
#			access => 'read'
#		};
#	}
#
#	my $subscriptions = $self->_get_subscriptions();
#	if(defined $subscriptions)
#	{
#		$output{subscriptions} = $subscriptions;
#		$output{subscriptions}->{title} = $self->_localize('subscriptions_tab');
#	}
#
#	my $discounts = $self->_get_discount_counters();
#	if(defined $discounts)
#	{
#		$output{volume_discounts} = $discounts;
#		$output{volume_discounts}->{title} = $self->_localize('discounts_tab');
#	}
#
#	return \%output;
#}
#
#sub set_info
#{
#	my $self = shift;
#	my $args = shift;
#
#	die '400' if(!$args);
#
#	my $info = $self->_get('info');
#	my $ph = $self->_get('ph');
#	my $obj = $self->_get('obj');
#
#	my @fields = qw(companyname salutation firstname midinit login out_date_format out_time_format i_distributor
#					out_date_time_format in_date_format in_time_format lastname address state zip i_rep shifted_billing_date
#					city country cont1 phone1 faxnum phone2 cont2 email discount_rate tax_id i_template
#					i_time_zone i_lang i_vd_plan i_billing_period send_invoices send_statistics i_number_scope);
#
#	my $hash = $self->_validate_args($args,\@fields);
#
#	if(defined $hash && %$hash)
#	{
#		$hash->{i_customer} = $ph->{i_customer};
#		$obj->update($hash);
#	}
#
#	$self->_set('info',$obj->get( $ph->{i_customer}, 0,  {get_services => 1} ));
#
#	return {success => {code => 200, content => $self->_localize('SUCCESS_UPDATED')}};
#}

#sub get_payment
#{
#	my $self = shift;
#
#	die '403' if (!($self->_get_access({attr => 'Customer Self Info', obj => 'WebForms'})));
#
#	my %output;
#	my $params = {payment_info => ['credit_limit','previous_credit_limit','temp_credit_limit','credit_limit_warning','unallocated_payments']};
#
#	foreach my $key(keys %$params)
#	{
#		foreach my $k(@{$params->{$key}})
#		{
#			my $attribute = $self->_get_attribute($k);
#			if($attribute)
#			{
#				$attribute->{access} = 'read';
#				$output{$key} = {attributes => {}} if !defined $output{$key};
#				$output{$key}->{attributes}->{$k} = $attribute;
#			}
#		}
#		$output{$key}->{title} = $self->_localize($key) if defined $output{$key};
#	}
#
#	if(defined $output{payment_info}->{attributes}->{temp_credit_limit})
#	{
#		my $info = $self->_get('info');
#		my $obj = $self->_get('obj');
#		my $credit_limit_info = $obj->get_credit_limit($info);
#		if($credit_limit_info->{temp_credit_limit})
#		{
#			$output{payment_info}->{attributes}->{temp_credit_limit}->{value} = $self->_format_price($credit_limit_info->{temp_credit_limit})
#				.' ('.$credit_limit_info->{valid_until_date}.' '.$credit_limit_info->{valid_until_time}.')';
#		}
#	}
#
#	if(defined $output{payment_info}->{attributes}->{credit_limit_warning} && index($output{payment_info}->{attributes}->{credit_limit_warning}->{value}, '%') == -1)
#	{
#		$output{payment_info}->{attributes}->{credit_limit_warning}->{value} = $self->_format_price($output{payment_info}->{attributes}->{credit_limit_warning}->{value});
#	}
#
#	my $cc_fields = $self->_get_cc_fields();
#	if($cc_fields)
#	{
#		if(defined $output{payment_info})
#		{
#			@{$output{payment_info}->{attributes}}{keys %$cc_fields} = values %$cc_fields;
#		}
#		else
#		{
#			$output{payment_info} = {attributes => $cc_fields};
#			$output{payment_info}->{title} = $self->_localize('payment_info');
#		}
#	}
#
#	my $paypal = $self->_get_paypal_fields();
#	if($paypal)
#	{
#		$output{paypal} = {title => 'PayPal'};
#		$output{paypal}->{attributes} = $paypal;
#	}
#
#	my $make_payment = $self->_get_payment_fields();
#	if($make_payment)
#	{
#		$output{make_payment} = {title => $self->_localize('make_payment')};
#		$output{make_payment}->{attributes} = $make_payment;
#	}
#
#	my $another_cc_fields = $self->_get_another_cc_fields();
#	if($another_cc_fields)
#	{
#		$output{another_cc_payment} = {title => $self->_localize('another_cc_payment')};
#		$output{another_cc_payment}->{attributes} = $another_cc_fields;
#	}
#
#	my $ppayments = $self->_get_ppayments();
#	if($ppayments)
#	{
#		$output{ppayments} = $ppayments;
#		$output{ppayments}->{title} = $self->_localize('ppayments');
#	}
#
#	return \%output;
#}

#sub get_features
#{
#	my $self = shift;
#	my %output;
#
#	die '403' if (!($self->_get_access({attr => 'Customer Self Info', obj => 'WebForms'})));
#
#	$params = {
#		voice_calls 	=> ['i_moh','call_recording','auto_record_outgoing','auto_record_incoming','auto_record_redirected',
#							'legal_intercept','rtpp_level','cli_trust_accept','cli_trust_supply','call_parking',
#							'park_prefix','release_prefix','first_login_greeting'],
#		incoming_calls 	=> ['endpoint_redirect','distinctive_ring_vpn','group_pickup','group_pickup_prefix'],
#		outgoing_calls 	=> ['cli','clir','cli_batch','display_number_check','display_name_override','centrex','clir_hide',
#							'clir_show','paging','paging_prefix']
#	};
#
#	foreach my $key(keys %$params)
#	{
#		foreach my $k(@{$params->{$key}})
#		{
#			my $attribute = $self->_get_attribute($k);
#			if($attribute)
#			{
#				$output{$key} = {attributes => {}} if !defined $output{$key};
#				$output{$key}->{attributes}->{$k} = $attribute;
#			}
#		}
#		$output{$key}->{title} = $self->_localize($key) if defined $output{$key};
#	}
#
#	return \%output;
#}

1;