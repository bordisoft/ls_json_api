package JsonApi::Internal;

use strict;
use warnings;
use utf8;
use Porta::Localization;
use Porta::AccessConfig;
use Porta::AccessLevel;
use Porta::AccessType;

my $vars = {};

sub _set
{
	my ($self,$key,$value) = @_;

	if($key && $value)
	{
		$vars->{$key} = $value;
	}
}

sub _get
{
	my ($self,$key) = @_;

	if($key && $key eq 'all')
	{
		return $vars;
	}
	elsif($key && defined($vars->{$key}))
	{
		return $vars->{$key};
	}
	else
	{
		return undef;
	}
}

sub _get_status
{
	my ($self,$realm,$info) = @_;
	my $status = 'ok';

	if("Account" eq $realm)
	{
		if($info->{'service_state'}->{'voice_fraud_suspicion'})
		{
			if($info->{'service_state'}->{'voice_fraud_suspicion'} eq '5')
			{
				$status = 'status_quarantine';
			}
			elsif($info->{'service_state'}->{'voice_fraud_suspicion'} eq '1')
			{
				$status = 'status_screening';
			}
		}
		elsif($info->{bill_closed})
		{
			$status = 'closed';
		}
		elsif($info->{bill_inactive})
		{
		    $status = 'inactive';
		}
		elsif($info->{customer_bill_suspended} && !($info->{cust_bill_suspension_delayed}))
		{
			$status = 'suspended';
		}
		elsif(defined($info->{blocked}) && $info->{blocked} eq 'Y')
		{
			$status = 'blocked';
		}
		elsif (defined($info->{customer_blocked}) && $info->{customer_blocked} eq 'Y')
		{
			$status = 'blocked';
		}
		elsif ($info->{account_expired})
		{
			$status = 'expired';
		}
		elsif ($info->{account_inactive})
		{
			$status = 'inactive';
		}
		elsif ($info->{credit_exceed})
		{
			$status = 'credit_exceed';
		}
		elsif ($info->{customer_credit_exceed})
		{
			$status = 'credit_exceed';
		}
		elsif ($info->{zero_balance})
		{
			$status = 'zero_balance';
		}
		elsif ($info->{cust_bill_suspension_delayed})
		{
			$status = 'suspended';
		}
	}
	else
	{
		if($info->{bill_closed})
		{
			$status = 'closed';
		}
		elsif($info->{blocked} eq 'Y')
		{
		    $status = 'blocked';
		}
		elsif($info->{bill_suspended} && !$info->{bill_suspension_delayed})
		{
			$status = 'suspended';
		}
		elsif($info->{status})
		{
			$status = 'credit_exceed';
		}
		elsif($info->{bill_suspension_delayed})
		{
			$status = 'suspended';
		}
		elsif($info->{frozen})
		{
			$status = 'frozen';
		}
	}

	return $status;
}

sub _get_service
{
	my ($self, $attribute) = @_;
	my $properties = $self->_attribute_properties($attribute);
	my $info = $self->_get('info');
	my $value = undef;

	if(defined $properties->{service} && $properties->{service} eq 'other')
	{
		if($self->_in_array(['clir_hide','clir_show'],$attribute))
		{
			my $matches = {};
			($matches->{clir_hide},$matches->{clir_show}) = $info->{services}->{clir}->{clir_rule}->{value} =~ /.+#\shide=(.+)\sshow=(.+)/ if($info->{services}->{clir}->{clir_rule}->{value});
			$value = defined $matches->{$attribute} ? $matches->{$attribute} : '';
		}
	}
	elsif(defined $properties->{service})
	{
		my @keys = split('->', $properties->{service});
		my $_value = $info->{services};
		foreach(@keys) { $_value = $_value->{$_}; }
		$value = $_value->{value};
	}

	return $value;
}

sub _validate_args
{
	my ($self,$args,$allowed_args) = @_;
	my $options_list = $self->_get('options_list');
	my $hash = {};
	if(!@$allowed_args)
	{
		my @keys = keys %$args;
		$allowed_args = \@keys;
	}

	foreach my $key (@$allowed_args)
	{
		if(defined($args->{$key}))
		{
			my $access = $self->_get_access($key);
			if($access eq 'update')
			{
				my $allowed_options = $self->_get_options($key);
				if(defined $allowed_options)
				{
					my $valid = 0;
					foreach my $i(@$allowed_options)
					{
						if(($args->{$key} eq $i->{value} || !$args->{$key} && !$i->{value}) && !$i->{sel})
						{
							$valid = 1;
							$hash->{$key} = $args->{$key} || '';
							$options_list->{$key} = undef;
							last;
						}
						elsif(($args->{$key} eq $i->{value} || !$args->{$key} && !$i->{value}) && $i->{sel})
						{
							$valid = 1;
							last;
						}

					}
					die '403' if !$valid;
				}
				else
				{
					my $value = $args->{$key};
					my $properties = $self->_attribute_properties($key);
					if(defined $properties->{type})
					{
						if("integer" eq $properties->{type})
						{
							$value = int($value);
						}
						elsif("float" eq $properties->{type})
						{
							$value = sprintf("%.2f", $value);
						}
					}
					$hash->{$key} = $value;
				}
			}
			else
			{
				die '403 no update access for '.$key." ";
			}
		}
	}

	$self->_set('options_list',$options_list);

	return $hash;
}

sub _get_formats()
{
	my $self = shift;
	my $formats = $self->_get('date_time_formats') || undef;
	if(!defined $formats)
	{
		my ($sec_short,$min_short,$hour_short,$mday_short,$mon_short,$year,$wday,$yday,$isdst) = localtime(time);
		$year += 1900;
		my $year_short = sprintf("%02d", $year % 100);
		my $mon = ($mon_short+1 >= 10) ? $mon_short+1 : '0'.($mon_short+1);
		my $mday = (int($mday_short) < 10) ? '0'.$mday_short : $mday_short;
		my @months_short = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
		my @months = qw(January February March April May June July August September October November December);
		my $sec = ($sec_short >= 10) ? $sec_short : '0'.$sec_short;
		my $min = ($min_short>= 10) ? $min_short : '0'.$min_short;
		my $hour = ($hour_short >= 10) ? $hour_short : '0'.$hour_short;
		my $period = ($hour_short >= 12) ? ' PM' : ' AM';
		my $hour_period = ($hour_short >= 12) ? ($hour_short eq 12 ? 12 : $hour_short - 12) : $hour_short;
		$formats = {
			date => [
				{ name=>$year.'-'.$mon.'-'.$mday, 									value=>'YYYY-MM-DD' },
				{ name=>$mon.'/'.$mday.'/'.$year, 									value=>'MM/DD/YYYY' },
				{ name=>$mon.'/'.$mday.'/'.$year_short, 							value=>'MM/DD/YY' },
				{ name=>$mday.'-'.$mon.'-'.$year, 									value=>'DD-MM-YYYY' },
				{ name=>$mday.'-'.$mon.'-'.$year_short, 							value=>'DD-MM-YY' },
				{ name=>$mday.'.'.$mon.'.'.$year, 									value=>'DD.MM.YYYY' },
				{ name=>$mday.'.'.$mon.'.'.$year, 									value=>'DD.MM.YY' },
				{ name=>$mday_short.'-'.$months_short[$mon_short].'-'.$year_short, 	value=>'D-MON-YY' },
				{ name=>$months_short[$mon_short].' '.$mday_short.', '.$year_short,	value=>'MON. D, YY' },
				{ name=>$mday_short.' '.$months_short[$mon_short].' '.$year_short, 	value=>'D MON. YY' },
				{ name=>$months[$mon_short].' '.$mday_short.', '.$year, 			value=>'MONTH D, YYYY' },
				{ name=>$mday_short.' '.$months[$mon_short].' '.$year,				value=>'D MONTH YYYY' },
				{ name=>$mon.'-'.$mday.'-'.$year, 									value=>'MM-DD-YYYY' }
			],
			time => [
				{ name=>$hour_period.':'.$min.':'.$sec.$period, value=>'HH12:MI:SS AM' },
				{ name=>$hour_short.':'.$min.':'.$sec, 			value=>'HH:MI:SS' },
				{ name=>$hour_short.'-'.$min.'-'.$sec, 			value=>'HH-MI-SS' },
				{ name=>$hour_period.':'.$min.$period, 			value=>'HH12:MI AM' },
				{ name=>$hour_short.':'.$min, 					value=>'HH:MI' },
				{ name=>$hour_short.'-'.$min, 					value=>'HH-MI' },
				{ name=>$hour.':'.$min.':'.$sec,				value=>'HH24:MI:SS'}
			],
			date_time => [
				{ name=>$year.'-'.$mon.'-'.$mday.' '.$hour_short.':'.$min.':'.$sec,												value=>'YYYY-MM-DD HH:MI:SS' },
				{ name=>$mon.'/'.$mday.'/'.$year.' '.$hour_short.':'.$min.':'.$sec,												value=>'MM/DD/YYYY HH:MI:SS' },
				{ name=>$mon.'/'.$mday.'/'.$year_short.' '.$hour_period.':'.$min.':'.$sec.$period, 								value=>'MM/DD/YY HH12:MI:SS AM' },
				{ name=>$mday.'-'.$mon.'-'.$year.' '.$hour_short.':'.$min.':'.$sec, 											value=>'DD-MM-YYYY HH:MI:SS' },
				{ name=>$mday.'-'.$mon.'-'.$year_short.' '.$hour_period.':'.$min.':'.$sec.$period, 								value=>'DD-MM-YY HH:MI:SS' },
				{ name=>$mday.'.'.$mon.'.'.$year.' '.$hour_period.':'.$min.':'.$sec.$period,									value=>'DD.MM.YYYY HH:MI:SS' },
				{ name=>$mday.'.'.$mon.'.'.$year.' '.$hour_period.':'.$min.':'.$sec.$period, 									value=>'DD.MM.YY HH:MI:SS' },
				{ name=>$mday_short.'-'.$months_short[$mon_short].'-'.$year_short.' '.$hour_period.':'.$min.':'.$sec.$period, 	value=>'D-MON-YY HH:MI:SS' },
				{ name=>$mon.'-'.$mday.'-'.$year.' '.$hour.':'.$min.':'.$sec, 													value=>'MM-DD-YYYY HH24:MI:SS' }
			]
		};
		$self->_set('date_time_formats',$formats);
	}
	return $formats;
}

sub _get_access
{
	my $self = shift;
	my $attribute = shift;
	my $acl_obj = undef;
	my $acl_attr = undef;
	my $access = $self->_get('access');

	if(ref($attribute) eq "HASH")
	{
		$acl_obj = $attribute->{obj};
		$acl_attr = $attribute->{attr};
		$attribute = $attribute->{obj}.$attribute->{attr};
	}

	if(!defined $access->{$attribute})
	{
		if(!defined $acl_obj || !defined $acl_attr)
		{
			my $properties = $self->_attribute_properties($attribute);

			return 0 if !defined $properties;

			$acl_obj = $properties->{access}->{obj};
			$acl_attr = $properties->{access}->{attr};
		}

		my $ph = $self->_get('ph');
		$access->{$attribute} = (Security->isAllowed($ph->{level}, ACCESS_UPDATE, $acl_obj, $acl_attr)) ? 'update' : ((Security->isAllowed($ph->{level}, ACCESS_READ, $acl_obj, $acl_attr)) ? 'read' : 0);
		$self->_set('access',$access);
	}

	return $access->{$attribute};
}

sub _get_destinations
{
	use lib "/usr/lib/perl5/vendor_perl/5.8.8";
	use Tie::Persistent;

	my $self = shift;
	my $file = "/tmp/destinations.db";
	my $destinations = {};
	my %DB;

	tie %DB, 'Tie::Persistent', $file, 'rw';

	if(!defined $DB{timestamp} || time - $DB{timestamp} > 60*60*24*30)
	{
		use Text::CSV_XS;

		my $csv = $ENV{'PORTAHOME_WEB'}.'/apache/destinations.csv';
		my $parser = Text::CSV_XS->new ({ sep_char => ",", quote_char => '"', binary => 1, auto_diag => 1 });
		open(my $fh, '<:encoding(utf8)', $csv) or die "500 Could not open '$csv' ";
		my $countries = $self->_get_options("iso_3166_1_a2");

		while (my $row = $parser->getline($fh))
		{
			$destinations->{$row->[1]} = {
				destination => $row->[1],
				iso_3166_1_a2 => $row->[2],
				country => undef,
				description => $row->[3] || undef
			};
			foreach(@$countries)
			{
				if($_->{value} eq $row->[2])
				{
					$destinations->{$row->[1]}->{country} = $_->{name};
					last;
				}
			}
		}
		close $fh;

		$DB{data} = $destinations;
		$DB{timestamp} = time;
		untie %DB;
	}
	else
	{
		$destinations = $DB{data};
	}

	return $destinations;
}

sub _search_destinations
{
	my ($self,$search_params) = @_;

	die "500" if !$search_params || ref($search_params) ne "HASH";

	my $search_by = $search_params->{search_by} || undef;
	my $pattern = $search_params->{pattern} || undef;

	die "500" if !$search_by || !$pattern;

	my $destinations = $self->_get_destinations();
	my $data = undef;

	if($search_by eq "destination")
	{
		while($pattern && !$data)
		{
			$data = { $pattern => $destinations->{$pattern} } if(defined $destinations->{$pattern});
			$pattern = substr($pattern,0,length($pattern)-1) if(!defined $destinations->{$pattern});
		}
	}
	elsif($self->_in_array(["iso_3166_1_a2","country","description"],$search_by))
	{
		foreach(keys %$destinations)
		{
			if($self->_in_array(["iso_3166_1_a2","country"],$search_by) && $pattern eq $destinations->{$_}->{$search_by}
				|| $search_by eq "description" && index($destinations->{$_}->{description},$pattern) != -1)
			{
				$data = {} if !$data;
				$data->{$_} = $destinations->{$_};
			}
		}
	}

	return $data;
}

sub _format_price
{
	my $self = shift;
	my $n = shift || undef;
	my $info = $self->_get('info');
	my $currency = shift || $info->{iso_4217};
	my $num;

	if($n)
	{
		$num = sprintf("%.2f", abs $n);
		$num = "($num)" if ($n < 0);
	}
	else
	{
		$num = '0.00';
	}

	return $num.' '.$currency;
}

sub _format_datetime
{
	my $self = shift;
	my $format = shift;
	my $value = shift;

	return undef if(!$value);

	my $ph = $self->_get('ph');
	my $tz1 = shift || $ph->{TZ};
	my $tz2 = shift || $ph->{TZ};
	my $converted;

	use Date::Parse;
	use Porta::Date;

	my $is_unixtime = !($value =~ /[^\d]/);
	my $_date = Porta::Date->new({-date => ($is_unixtime ? $value : str2time($value)), -format => 'unixtime'});
	$value = $_date->asISO(($is_unixtime ? $tz1 : "UTC"));
	my $porta_date = Porta::Date->new({-date => $value, -format => 'iso', -tz => $tz1});

	if('default' eq $format)
	{
		$converted = $porta_date->asISO($tz2);
	}
	elsif('unixtime' eq $format)
	{
		$converted = str2time($porta_date->asISO($tz2));
	}
	else
	{
		$converted = Porta::Date->transformDate($porta_date->asISO($tz2), "YYYY-MM-DD HH24:MI:SS", $format);
	}

	return $converted;
}

sub _localize
{
	my ($self,$msg) = @_;
	my $locale = $self->_get('locale');
	my %p = ();

	if(ref($msg) eq "HASH")
	{
		%p = %{$msg->{p}} if $msg->{p};
		Porta::utf_decode_ref(\%p) if %p;
		$msg = $msg->{msg};
	}

	if(!defined $locale->{$msg})
	{
		my $properties;
		my $file;
		my $constant;

		$properties = $self->_get_locale_properties($msg);
		if(!defined $properties)
		{
			$properties = $self->_attribute_properties($msg);
			if(!defined $properties)
			{
				$self->_dump("Cand't find translation for ".$msg);
				return undef;
			}
			$file = $properties->{locale}->{file};
			$constant = $properties->{locale}->{const};
		}
		else
		{
			$file = $properties->{locale_file};
			$constant = $properties->{locale_const};
		}

		if('locale.xml' eq $file)
		{
			use XML::DOM;

			my $info = $self->_get('info');
			my $parser = new XML::DOM::Parser;
			my $xml_file = $ENV{'PORTAHOME_WEB'}.'/apache/ls_json_api/locale.xml';
			my $locales = {};
			my $dom;

			eval { $dom = $parser->parsefile($xml_file); };
			if($@) { $self->_dump( 'error parsing file '.$xml_file.":\n".$@."\n", 1	 ); next; }

			my ($root) = $dom->getElementsByTagName('root');
			if (!$root)
			{
				$dom->dispose;
				die '700';
			}

			for my $_msg($root->getElementsByTagName ("message", 0))
			{
				my $attr = $_msg->getAttributeNode("name");
				my $msg_name = $attr->getValue();
				my $languages = ['en'];
				push @$languages, $info->{i_lang} if 'en' ne $info->{i_lang};

				foreach my $_lang(@$languages)
				{
					my ($lang) = $_msg->getElementsByTagName($_lang, 0);
					if($lang)
					{
						my $text = '';
						foreach my $child ($lang->getChildNodes())
						{
							if($child->getNodeType == TEXT_NODE)
							{
								$text = $child->getNodeValue();
								last;
							}
						}

						if (defined($text))
						{
							utf8::decode($text);
							utf8::upgrade($text);
							$locales->{$msg_name}->{$_lang} = $text ;
						}
					}
					elsif('en' eq $_lang)
					{
						$dom->dispose;
						die '700';
					}
				}
			}
			$dom->dispose;
			foreach my $msg_name(keys %$locales)
			{
				$locale->{$msg_name} = defined $locales->{$msg_name}->{$info->{i_lang}} ? $locales->{$msg_name}->{$info->{i_lang}} : $locales->{$msg_name}->{en};
			}
		}
		else
		{
			my $ph = $self->_get('ph');
			my $info = $self->_get('info');
			my $l = new Porta::Localization( {lang => $info->{i_lang}, files => [$file], ph => $ph} );
			$locale->{$msg} = $l->translate($constant);
		}

		$self->_set('locale', $locale);
	}

	if(%p)
	{
		my $result;
		$result = eval 'qq('.$locale->{$msg}.')';
		utf8::decode($result);

		return $result;
	}

	return $locale->{$msg};
}

sub _in_array
{
	my ($self,$arr,$search_for) = @_;
	my %items = map {$_ => 1} @$arr;

	return (exists($items{$search_for}))?1:0;
}

sub _dump
{
	use Data::Dumper;

	my $self = shift;
	foreach(@_) { print STDERR Dumper($_); }
}

sub _attribute_properties
{
 	my ($self,$attribute) = @_;
 	my $realm = $self->_get('realm');
 	my $realm_file = lc($realm).'.xml';
 	my $acl_obj = $realm.'s';

 	my $attribute_properties = {
# 		Info
		email => {locale => {const=>'Email',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'email'}, type => 'string'},
		opening_balance => {locale => {const=>'Opening Balance',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'opening_balance'}, format => 'price'},
		refunds => {locale => {const=>'Refunds',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'refunds'}, format => 'price'},
		i_customer_site => {locale => {const=>'Customer_Site',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'i_customer_site'}},
		discount_rate => {locale => {const=>'Subscription_Discount_Rate',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'discount_rate'}, unit => '%'},
		tax_id => {locale => {const=>'Tax ID',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'tax_id'}},
		companyname => {locale => {const=>'Company Name',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'companyname'}, type => 'string'},
		salutation => {locale => {const=>'Mr_Ms',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'salutation'}, type => 'string'},
		firstname => {locale => {const=>'First Name',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'firstname'}, type => 'string'},
		midinit => {locale => {const=>'M.I.',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'midinit'}, type => 'string'},
		lastname => {locale => {const=>'Last Name',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'lastname'}, type => 'string'},
		address => {locale => {const=>'Address',file=>'customer.xml'}, access => {obj=>$acl_obj,attr=>'address'}, type => 'string'},
		baddr1 => {locale => {const=>'Address',file=>'account.xml'}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'baddr1'}, type => 'string'},
		state => {locale => {const=>'Province_State',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'state'}, type => 'string'},
		zip => {locale => {const=>'Postal Code',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'zip'}, type => 'string'},
		city => {locale => {const=>'City',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'city'}, type => 'string'},
		country => {locale => {const=>'Country_Region',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'country'}, type => 'string'},
		cont1 => {locale => {const=>'Contact',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'cont1'}, type => 'string'},
		phone1 => {locale => {const=>'Phone',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'phone1'}, type => 'string'},
		faxnum => {locale => {const=>'Fax',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'faxnum'}, type => 'string'},
		phone2 => {locale => {const=>'Alt_Phone',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'phone2'}, type => 'string'},
		cont2 => {locale => {const=>'Alt_Contact',file=>$realm_file}, access => {obj=>("Account" eq $realm ? "Subscribers" : $acl_obj),attr=>'cont2'}, type => 'string'},
		login => {locale => {const=>'Login',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'login'}, type => 'string'},
		password => {locale => {const=>'Password',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'password'}, type => 'string'},
		activation_date => {locale => {const=>'Activation Date',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'activation_date'}, format => 'date'},
		expiration_date => {locale => {const=>'Expiration Date',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'expiration_date'}, format => 'date'},
		life_time => {locale => {const=>'Last Usage',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'life_time'}, format => 'date'},
		issue_date => {locale => {const=>'Issue Date',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'issue_date'}, format => 'date'},
		first_usage => {locale => {const=>'First Usage',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'first_usage'}, format => 'date'},
		last_usage => {locale => {const=>'Last Usage',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'last_usage'}, format => 'date_time'},
		last_recharge => {locale => {const=>'Last Recharge',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'last_recharge'}, format => 'date_time'},
		i_time_zone => {locale => {const=>'Time Zone',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'i_time_zone'}, type => 'integer'},
		i_lang => {locale => {const=>'Locale_Language',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'i_lang'}, type => 'string'},
		out_date_format => {locale => {const=>'Date',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'out_date_format'}, type => 'string'},
		out_time_format => {locale => {const=>'Time',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'out_time_format'}, type => 'string'},
		out_date_time_format => {locale => {const=>'Date_Time',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'out_date_time_format'}, type => 'string'},
		in_date_format => {locale => {const=>'Date',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'in_date_format'}, type => 'string'},
		in_time_format => {locale => {const=>'Time',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'in_time_format'}, type => 'string'},
		i_vd_plan => {locale => {const=>'Discount Plan',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'i_vd_plan'}, type => 'integer'},
		i_distributor => {locale => {const=>'Distributor',file=>'account.xml'}, access => {obj=>$acl_obj,attr=>'i_distributor'}, type => 'integer'},
		i_billing_period => {locale => {const=>'Billing Period',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'i_billing_period'}},
		send_invoices => {locale => {const=>'Send_Invoices',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'send_invoices'}, type => 'string'},
		send_statistics => {locale => {const=>'Send Statistics',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'send_statistics'}, type => 'string'},
		ecommerce_enabled => {locale => {const=>'E-commerce Enabled',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'ecommerce_enabled'}, type => 'string'},
		billing_model => {locale => {const=>'Type',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'billing_model'}},
		um_enabled => {locale => {const=>'UM Enabled',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'um_enabled'}, type => 'string'},
		ppm_enabled => {locale => {const=>'PPM_Enabled',file=>'customer.xml'}, access => {obj=>$acl_obj,attr=>'ppm_enabled'}, type => 'string'},
		drm_enabled => {locale => {const=>'DRM_Enabled',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'drm_enabled'}, type => 'string'},
		iso_4217 => {locale => {const=>'Currency',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'iso_4217'}},
		tz => {locale => {const=>'Time Zone',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'tz'}},
		bm_name => {locale => {const=>'Type',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'bm_name'}},
		ctype => {locale => {const=>'Type',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'ctype'}},
		balance => {locale => {const=>'Balance',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'balance'}, format => 'price'},
		id => {locale => {const=>'Account',file=>'dashboard.xml'}, access => {obj=>'Accounts',attr=>'id'}},
		i_do_batch => {locale => {const=>'Auto_provision_DIDs_Via_Batch',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'i_do_batch'}, type => 'integer'},
		i_rep => {locale => {const=>'Representative',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'i_rep'}, type => 'integer'},
		shifted_billing_date => {locale => {const=>'Shift_Billing_Date_To',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'shifted_billing_date'}},
		i_template => {locale => {const=>'Invoice Template',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'i_template'}, type => 'integer'},
		i_number_scope => {locale => {const=>'Invoice_Number_Sequence',file=>'globals.xml'}, access => {obj=>'Customers',attr=>'i_number_scope'}},
		credit_limit => {locale => {const=>'Current Credit Limit',file=>'payment_info.xml'}, access => {obj=>$acl_obj,attr=>'credit_limit'}, format=>'price'},
		previous_credit_limit => {locale => {const=>'Permanent Credit Limit',file=>'payment_info.xml'}, access => {obj=>'Customers',attr=>'perm_credit_limit'}, format=>'price'},
		temp_credit_limit => {locale => {const=>'Temporary Credit Limit Increase',file=>'payment_info.xml'}, access => {obj=>'Customers',attr=>'temp_credit_limit'}},
		credit_limit_warning => {locale => {const=>'PM Credit limit warning',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'credit_limit_warning'}},
		unallocated_payments => {locale => {const=>'Unallocated_Payments',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'unallocated_payments'}, format=>'price'},
		i_moh => {locale => {const=>'Music On Hold',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'i_moh'}, type => 'integer'},
		iso_639_1 => {locale => {const=>'Preferred IVR Language',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'iso_639_1'}, type => 'string'},
		i_routing_plan => {locale => {const=>'Default_Routing_Plan',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'i_routing_plan'}, type => 'integer'},
		max_forwards => {locale => {const=>'Maximum Forwards',file=>'follow_me.xml'}, access => {obj=>'Follow_Me',attr=>'max_forwards'}, type => 'integer'},
		timeout => {locale => {const=>'FM_Timeout_sec',file=>'follow_me.xml'}, access => {obj=>'Follow_Me',attr=>'timeout'}, type => 'integer'},
		sequence => {locale => {const=>'FM_Order',file=>'follow_me.xml'}, access => {obj=>'Follow_Me',attr=>'sequence'}, type => 'string'},
		redirect_number => {locale => {const=>'Associated number',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'redirect_number'}},
#		CC Fields
		cc_i_payment_method => {locale => {const=>'PM Preferred Payment Method',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'i_payment_method'}, type => 'integer'},
		cc_number => {locale => {const=>'PM Credit Card No.',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'number'}, type => 'string'},
		cc_exp_date => {locale => {const=>'PM Exp. Date',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'exp_date'}},
		cc_cvv => {locale => {const=>'PM CVV',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'cvv'}, type => 'string'},
		cc_name => {locale => {const=>'PM Name on Card',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'name'}, type => 'string'},
		cc_address => {locale => {const=>'PM Address',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'address'}, type => 'string'},
		cc_city => {locale => {const=>'PM City',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'city'}, type => 'string'},
		cc_iso_3166_1_a2 => {locale => {const=>'PM Country',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'iso_3166_1_a2'}, type => 'string'},
		cc_i_country_subdivision => {locale => {const=>'PM State',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'i_country_subdivision'}, type => 'string'},
		cc_zip => {locale => {const=>'PM Postal Code',file=>'payment_info.xml'}, access => {obj=>'Credit_Cards',attr=>'zip'}, type => 'string'},
#		Service Features
		call_recording => {locale => {const=>'Call_Recording',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_call_recording'}, service_flag => 'call_recording'},
		cli => {locale => {const=>'Override_Identity',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_cli'}, service_flag => 'cli'},
		call_parking => {locale => {const=>'Call_Parking',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'srv_call_parking'}, service_flag => 'call_parking'},
		clir => {locale => {const=>'Hide_CLI',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'srv_clir'}, service_flag => 'clir'},
		group_pickup => {locale => {const=>'Group_Pickup',file=>'service_features.xml'}, access => {obj=>'Customers',attr=>'srv_group_pickup'}, service_flag => 'group_pickup'},
		paging => {locale => {const=>'Paging_Intercom',file=>'service_features.xml'}, access => {obj=>'Customers',attr=>'srv_paging'}, service_flag => 'paging'},
		auto_record_outgoing => {locale => {const=>'Auto_Record_Outgoing_Calls',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_call_recording'}, service => 'other'},
    	auto_record_incoming => {locale => {const=>'Auto_Record_Incoming_Calls',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_call_recording'}, service => 'other'},
    	auto_record_redirected => {locale => {const=>'Auto_Record_Redirected_Calls',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_call_recording'}, service => 'other'},
		cli_trust_accept => {locale => {const=>'Accept_Caller_Identity',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_cli_trust'}, service => 'other'},
		cli_trust_supply => {locale => {const=>'Supply_Caller_Identity',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_cli_trust'}, service => 'other'},
		legal_intercept => {locale => {const=>'Legal_intercept',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'srv_legal_intercept'}, service_flag => 'legal_intercept'},
		rtpp_level => {locale => {const=>'RTP_Proxy',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_rtpp_level'}, service_flag => 'rtpp_level'},
 		endpoint_redirect => {locale => {const=>'endpoint_redirect',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_endpoint_redirect'}, service_flag => 'endpoint_redirect'},
		clir_hide => {locale => {const=>'Hide_CLI_prefix',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'srv_clir'}, service => 'other'},
		clir_show => {locale => {const=>'Show_CLI_prefix',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'srv_clir'}, service => 'other'},
		cli_batch => {locale => {const=>'Allowed_Batch',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_cli'}, service => 'other'},
		display_number_check => {locale => {const=>'Override_Display_Number',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_display_number_check'}, service => 'cli->display_number_check'},
		display_name_override => {locale => {const=>'Override_Display_Name',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_display_name_override'}, service => 'cli->display_name_override'},
		centrex => {locale => {const=>'Identity',file=>'service_features.xml'}, access => {obj=>$acl_obj,attr=>'srv_centrex'}, service => 'cli->centrex'},
		call_park_prefix => {locale => {const=>'Park_prefix',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'srv_call_parking'}, service => 'call_parking->park_prefix'},
		call_release_prefix => {locale => {const=>'Release_prefix',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'srv_call_parking'}, service => 'call_parking->release_prefix'},
		first_login_greeting => {locale => {const=>'First_login_greeting',file=>'customer.xml'}, access => {obj=>'Customers',attr=>'srv_first_login_greeting'}, service_flag => 'first_login_greeting'},
		voice_service_policy => {locale => {const=>'Service_Policy',file=>'account.xml'}, access => {obj=>'Accounts',attr=>'srv_voice_service_policy'}, service => 'voice_service_policy->id'},
		distinctive_ring_vpn => {locale => {const=>'Voice_VPN_distinctive_ring',file=>$realm_file}, access => {obj=>$acl_obj,attr=>'srv_distinctive_ring_vpn'}, service_flag => 'distinctive_ring_vpn'},
		group_pickup_prefix => {locale => {const=>'Group_Pickup_Prefix',file=>'service_features.xml'}, access => {obj=>'Customers',attr=>'srv_group_pickup'}, service => 'group_pickup->group_pickup_prefix'},
		call_processing => {locale => {const=>'Call_Processing',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_call_processing'}, service_flag => 'call_processing'},
		default_action => {locale => {const=>'Default_Action',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_default_action'}, service_flag => 'default_action'},
		clip => {locale => {const=>'CLIP_Enabled',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_clip'}, service_flag => 'clip'},
		call_wait_limit => {locale => {const=>'Disable_Call_Waiting',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_call_wait_limit'}, service_flag => 'call_wait_limit'},
		paging_prefix => {locale => {const=>'Paging_Prefix',file=>'service_features.xml'}, access => {obj=>'Customers',attr=>'srv_paging'}, service => 'paging->paging_prefix'},
		favourite_numbers => {locale => {const=>'Favorite_Numbers',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_favourite_numbers'}, service_flag => 'favourite_numbers'},
		emergency => {locale => {const=>'E911',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_emergency'}, service_flag => 'emergency'},
		call_barring => {locale => {const=>'Call_Barring',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_call_barring'}, service_flag => 'call_barring'},
		display_number => {locale => {const=>'Display_Number',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_display_number'}, service => 'cli->display_number'},
		display_name => {locale => {const=>'Display_Name',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_display_name'}, service => 'cli->display_name'},
		phonebook => {locale => {const=>'Abbrev_Dial_Length',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_phonebook'}, service_flag => 'phonebook'},
		max_favorites => {locale => {const=>'Max_Favorite_numbers',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_phonebook'}, service => 'phonebook->max_favorites'},
		favorite_change_lock_days => {locale => {const=>'Favorite_Change_Lock_Days',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_phonebook'}, service => 'phonebook->favorite_change_lock_days'},
		favorite_allowed_patterns => {locale => {const=>'Favorite_Allowed_Patterns',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_phonebook'}, service => 'phonebook->favorite_allowed_patterns'},
		voice_pass_through => {locale => {const=>'Call_Via_IVR',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_voice_pass_through'}, service_flag => 'voice_pass_through'},
		outgoing_access_number => {locale => {const=>'Voice_Application',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_outgoing_access_number'}, service => 'voice_pass_through->outgoing_access_number'},
		voice_location => {locale => {const=>'Voice_Location',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_voice_location'}, service_flag => 'voice_location'},
		allow_roaming => {locale => {const=>'Mobility',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_allow_roaming'}, service => 'voice_location->allow_roaming'},
		voice_authentication => {locale => {const=>'Service_Unblock_Code',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_voice_authentication'}, service => 'voice_authentication->pin'},
		primary_location => {locale => {const=>'Current_Location',file=>'service_features.xml'}, access => {obj=>'Accounts',attr=>'srv_primary_location'}, service => 'voice_location->primary_location'},
 	};

 	return $attribute_properties->{$attribute} || undef;
}

sub _get_locale_properties
{
	my ($self,$constant) = @_;
 	my $realm_file = lc($self->_get('realm')).'.xml';

	my $locale = {
		SUCCESS => {locale_const => 'SUCCESS', locale_file => 'locale.xml'},
		SUCCESS_UPDATED => {locale_const => 'SUCCESS_UPDATED', locale_file => 'locale.xml'},
		NOTICE => {locale_const => 'Notice', locale_file => 'belogview.xml'},
		WARNING => {locale_const => 'Warning', locale_file => 'belogview.xml'},
		ERROR => {locale_const => 'ERROR', locale_file => 'locale.xml'},
		JS_MAND_CHECKBOX => {locale_const => 'JS_MAND_CHECKBOX', locale_file => 'locale.xml'},
		JS_SELECT_ITEM => {locale_const => 'JS_SELECT_ITEM', locale_file => 'locale.xml'},
		JS_INVALID_CHARACTER => {locale_const => 'JS_INVALID_CHARACTER', locale_file => 'locale.xml'},
		JS_MAND_FIELD => {locale_const => 'JS_MAND_FIELD', locale_file => 'locale.xml'},
		JS_ENTER_VALID_EMAIL => {locale_const => 'JS_ENTER_VALID_EMAIL', locale_file => 'locale.xml'},
		HELLO => {locale_const => 'HELLO', locale_file => 'locale.xml'},
		UPDATE => {locale_const => 'UPDATE', locale_file => 'locale.xml'},
		CHANGE_PASS => {locale_const => 'Change Password', locale_file => 'globals.xml'},
		LOGOUT => {locale_const => 'cm_Logout', locale_file => 'globals.xml'},
		TITLE_DASHBOARD => {locale_const => 'TITLE_DASHBOARD', locale_file => 'locale.xml'},
		TITLE_INFO => {locale_const => 'TITLE_INFO', locale_file => 'locale.xml'},
		TITLE_PAYMENT => {locale_const => 'TITLE_PAYMENT', locale_file => 'locale.xml'},
		TITLE_FEATURES => {locale_const =>'TITLE_FEATURES', locale_file => 'locale.xml'},
		ERROR_400 => {locale_const => 'ERROR_400', locale_file => 'locale.xml'},
		ERROR_403 => {locale_const => 'Forbidden', locale_file => 'tariff_wizard.xml'},
		ERROR_409 => {locale_const => 'alert_New_Passwords_dont_match', locale_file => 'login.xml'},
		ERROR_410 => {locale_const => 'alert_new_password_should_not_match_old', locale_file => 'login.xml'},
		ERROR_420 => {locale_const => 'alert_Old_password_is_wrong', locale_file => 'login.xml'},
		ERROR_421 => {locale_const => 'ERROR_421', locale_file => 'locale.xml'},
		ERROR_500 => {locale_const => 'ERROR_500', locale_file => 'locale.xml'},
		ERROR_600 => {locale_const => 'ERROR_600', locale_file => 'locale.xml'},
		ERROR_601 => {locale_const => 'ERROR_601', locale_file => 'locale.xml'},
		ERROR_602 => {locale_const => 'ERROR_602', locale_file => 'locale.xml'},
		ERROR_603 => {locale_const => 'ERROR_603', locale_file => 'locale.xml'},
		ERROR_604 => {locale_const => 'ERROR_604', locale_file => 'locale.xml'},
		ERROR_605 => {locale_const => 'ERROR_605', locale_file => 'locale.xml'},
		ERROR_606 => {locale_const => 'ERROR_606', locale_file => 'locale.xml'},
		ERROR_607 => {locale_const => 'ERROR_607', locale_file => 'locale.xml'},
		ERROR_608 => {locale_const => 'ERROR_608', locale_file => 'locale.xml'},
		ERROR_609 => {locale_const => 'ERROR_609', locale_file => 'locale.xml'},
		ERROR_610 => {locale_const => 'ERROR_610', locale_file => 'locale.xml'},
		ERROR_700 => {locale_const => 'ERROR_700', locale_file => 'locale.xml'},
		status => {locale_const => 'Status', locale_file => $realm_file},
		closed => {locale_const => 'Bill_Closed', locale_file => 'customer.xml'},
		blocked => {locale_const => 'Blocked', locale_file => 'customer.xml'},
		suspended => {locale_const => 'Bill_Suspended', locale_file => 'customer.xml'},
		credit_exceed => {locale_const => 'Credit exceed', locale_file => 'customer.xml'},
		delayed => {locale_const => 'status_Bill_Suspension_Delayed_short', locale_file => 'customer.xml'},
		frozen => {locale_const => 'Frozen', locale_file => 'customer.xml'},
		status_quarantine => {locale_const => 'status_quarantine', locale_file => 'account.xml'},
		status_screening => {locale_const => 'status_screening', locale_file => 'account.xml'},
		inactive => {locale_const => 'status_bill_inactive', locale_file => 'account.xml'},
		customer_suspended => {locale_const => 'Bill_Suspended', locale_file => 'account.xml'},
		expired => {locale_const => 'status_expired', locale_file => 'account.xml'},
		inactive => {locale_const => 'Inactive', locale_file => 'account.xml'},
		zero_balance => {locale_const => 'status_zero_balance', locale_file => 'account.xml'},
		recent_calls => {locale_const => 'Recent Calls', locale_file => 'dashboard.xml'},
		features => {locale_const => 'Features', locale_file => 'dashboard.xml'},
		invoice => {locale_const => 'Invoice', locale_file => 'dashboard.xml'},
		phone_lines => {locale_const => 'Phone Lines', locale_file => 'dashboard.xml'},
		sip => {locale_const => 'SIP', locale_file => $realm_file},
		'time' => {locale_const => 'Time', locale_file => $realm_file},
		duration => {locale_const => 'Duration', locale_file => 'dashboard.xml'},
		date => {locale_const => 'Date', locale_file => $realm_file},
		pass_changed => {locale_const => 'Password has been successfully changed', locale_file => 'login.xml'},
		account_info_tab => {locale_const => 'tab_Account_Info', locale_file => 'account.xml'},
		user_interface => {locale_const => 'tab_Self_care_Info', locale_file => 'account.xml'},
		life_cycle => {locale_const => 'tab_Life_Cycle', locale_file => 'account.xml'},
		subscriber => {locale_const => 'tab_Subscriber', locale_file => 'account.xml'},
		subscriptions => {locale_const => 'tab_Subscriptions', locale_file => 'subscriptions.xml'},
		discounts => {locale_const => 'tab_Volume_Discounts', locale_file => $realm_file},
		additional_info => {locale_const => 'tab_Additional_Info', locale_file => $realm_file},
		address_info => {locale_const => 'tab_Address_Info', locale_file => 'customer.xml'},
		voucher => {locale_const => 'Voucher', locale_file => 'account.xml'},
		debit => {locale_const => 'Debit', locale_file => 'account.xml'},
		credit => {locale_const => 'Credit', locale_file => 'account.xml'},
		customer_default => {locale_const => 'Customer\'s default', locale_file => 'account.xml'},
		yes => {locale_const => 'Yes', locale_file => 'globals.xml'},
		'no' => {locale_const => 'No', locale_file => 'globals.xml'},
		daily => {locale_const => 'period_daily', locale_file => 'globals.xml'},
		weekly => {locale_const => 'period_weekly', locale_file => 'globals.xml'},
		'bi-weekly' => {locale_const => 'period_bi-weekly', locale_file => 'globals.xml'},
		monthly => {locale_const => 'period_monthly', locale_file => 'globals.xml'},
		'monthly (anniversary)' => {locale_const => 'period_monthly (anniversary)', locale_file => 'globals.xml'},
		'30 days' => {locale_const => 'period_30 days', locale_file => 'globals.xml'},
		mobility_stationary => {locale_const => 'mobility_stationary', locale_file => 'service_features.xml'},
		mobility_roaming => {locale_const => 'mobility_roaming', locale_file => 'service_features.xml'},
		default_cust_class => {locale_const => 'Customer Class Default', locale_file => 'customer.xml'},
		full_stats => {locale_const => 'Full statistics', locale_file => 'customer.xml'},
		summary_only => {locale_const => 'Summary only', locale_file => 'customer.xml'},
		do_not_send => {locale_const => 'Do not send', locale_file => 'customer.xml'},
		no_forward => {locale_const => 'FM_No_Forwarding', locale_file => 'follow_me.xml'},
		follow_me => {locale_const => 'FM_Follow_Me', locale_file => 'follow_me.xml'},
		advanced_forward => {locale_const => 'FM_Advanced_Fw', locale_file => 'follow_me.xml'},
		fw_sip_uri => {locale_const => 'FM_Fw_SIP_URI', locale_file => 'follow_me.xml'},
		fw_cld => {locale_const => 'FM_Fw_CLD', locale_file => 'follow_me.xml'},
		never => {locale_const => 'Never', locale_file => 'service_features.xml'},
		Different_From_The_Used_Identity => {locale_const => 'Different_From_The_Used_Identity', locale_file => 'service_features.xml'},
		Ruled_Out_By_The_Identity_Constraint => {locale_const => 'Ruled_Out_By_The_Identity_Constraint', locale_file => 'service_features.xml'},
		always => {locale_const => 'Always', locale_file => 'service_features.xml'},
		product_default => {locale_const => 'Products_Default', locale_file => 'service_features.xml'},
		enabled => {locale_const => 'Enabled', locale_file => 'service_features.xml'},
		disabled => {locale_const => 'Disabled', locale_file => 'service_features.xml'},
		account_has_its_own => {locale_const => 'account_has_its_own', locale_file => 'service_features.xml'},
		Different_From_Account_ID_And_Aliases => {locale_const => 'Different_From_Account_ID_And_Aliases', locale_file => 'service_features.xml'},
		Different_From_Customer_Accounts => {locale_const => 'Different_From_Customer_Accounts', locale_file => 'service_features.xml'},
		Different_From_Accounts_In_The_Batch => {locale_const => 'Different_From_Accounts_In_The_Batch', locale_file => 'service_features.xml'},
		automatic => {locale_const => 'txt_Automatic', locale_file => 'globals.xml'},
		use_default => {locale_const => 'Use_default', locale_file => 'service_features.xml'},
		Direct => {locale_const => 'Direct', locale_file => 'service_features.xml'},
		Optimal => {locale_const => 'Optimal', locale_file => 'service_features.xml'},
		On_NAT => {locale_const => 'On_NAT', locale_file => 'service_features.xml'},
		reject => {locale_const => 'reject', locale_file => 'call_proc.xml'},
		sip_ua => {locale_const => 'sip_ua', locale_file => 'call_proc.xml'},
		sip_ua__forward => {locale_const => 'sip_ua__forward', locale_file => 'call_proc.xml'},
		sip_ua__voicemail => {locale_const => 'sip_ua__voicemail', locale_file => 'call_proc.xml'},
		sip_ua__forward__voicemail => {locale_const => 'sip_ua__forward__voicemail', locale_file => 'call_proc.xml'},
		forward__voicemail => {locale_const => 'forward__voicemail', locale_file => 'call_proc.xml'},
		voicemail => {locale_const => 'voicemail', locale_file => 'call_proc.xml'},
		All_Available_Routes => {locale_const => 'All_Available_Routes', locale_file => 'globals.xml'},
		none => {locale_const => 'None', locale_file => $realm_file},
		Favor_forwarder => {locale_const => 'Favor_forwarder', locale_file => 'service_features.xml'},
		Caller_only => {locale_const => 'Caller_only', locale_file => 'service_features.xml'},
		Peak_Level0 => {locale_const => 'Peak_Level0', locale_file => 'discounts.xml'},
		Peak_Level1 => {locale_const => 'Peak_Level1', locale_file => 'discounts.xml'},
		Peak_Level2 => {locale_const => 'Peak_Level2', locale_file => 'discounts.xml'},
		no_invoice => {locale_const => 'Do not create invoice', locale_file => 'customer.xml'},
		subscription => {locale_const => 'Subscription', locale_file => 'subscriptions.xml'},
		start_date => {locale_const => 'Subscr_Start_Date', locale_file => 'subscriptions.xml'},
		finish_date => {locale_const => 'Subscr_Finish_Date', locale_file => 'subscriptions.xml'},
		billed_to => {locale_const => 'Subscr_Billed_to', locale_file => 'subscriptions.xml'},
		dg_name => {locale_const => 'Destination Group', locale_file => 'discounts.xml'},
		service_name => {locale_const => 'Service', locale_file => 'discounts.xml'},
		peak_level => {locale_const => 'Peak_Level', locale_file => 'discounts.xml'},
		threshold => {locale_const => 'Threshold', locale_file => 'discounts.xml'},
		used => {locale_const => 'Used', locale_file => $realm_file},
		remaining => {locale_const => 'Remaining', locale_file => $realm_file},
		current_discount => {locale_const => 'Current Discount', locale_file => $realm_file},
		next_discount => {locale_const => 'Next Discount Level', locale_file => $realm_file},
		account_id => {locale_const => 'Account', locale_file => 'dashboard.xml'},
		cld => {locale_const => 'To', locale_file => 'call_proc.xml'},
		charged_amount => {locale_const => 'Cost', locale_file => 'dashboard.xml'},
		features => {locale_const => 'Features', locale_file => 'dashboard.xml'},
		due_date => {locale_const => 'Due Date', locale_file => 'invoices.xml'},
		amount_due => {locale_const => 'Amount Due', locale_file => 'invoices.xml'},
		invoice_status_desc => {locale_const => 'Payment Status', locale_file => 'invoices.xml'},
		Individual_For_Env => {locale_const => 'Individual_For_Env', locale_file => 'globals.xml'},
		Individual_For_Customer => {locale_const => 'Individual_For_Customer', locale_file => 'globals.xml'},
		Individual_For_Reseller => {locale_const => 'Individual_For_Reseller', locale_file => 'globals.xml'},
		model => {locale_const => 'Type', locale_file => 'account.xml'},
		pay_to => {locale_const => 'Pay to the order of', locale_file => 'make_payment.xml'},
		amount => {locale_const => 'Amount', locale_file => 'make_payment.xml'},
		'use' => {locale_const => 'cm_Use_Stored_Card', locale_file => 'globals.xml'},
		'Balance Driven' => {locale_const => 'pperiod_Balance Driven', locale_file => 'p_payment.xml'},
		accepted => {locale_const => 'Accepted', locale_file => 'p_payment.xml'},
		discontinued => {locale_const => 'Discontinued', locale_file => 'p_payment.xml'},
		number_payments => {locale_const => 'Number of Transfers', locale_file => 'p_payment.xml'},
		i_periodical_payment_period => {locale_const => 'Frequency', locale_file => 'p_payment.xml'},
		balance_threshold => {locale_const => 'Balance Threshold', locale_file => 'p_payment.xml'},
		payment_info => {locale_const => 'tab_Payment_Info', locale_file => $realm_file},
		make_payment => {locale_const => 'sn_Make_Payment', locale_file => 'make_payment.xml'},
		another_cc_payment => {locale_const => 'cm_Use_Other_Card', locale_file => 'globals.xml'},
		ppayments => {locale_const => 'sn_Periodical_Payments', locale_file => 'p_payment.xml'},
		voucher_topup => {locale_const => 'mn_Recharge_Using_Voucher', locale_file => 'globals.xml'},
		edit => {locale_const => 'Edit', locale_file => 'globals.xml'},
		add => {locale_const => 'cm_Add_New', locale_file => 'globals.xml'},
		'delete' => {locale_const => 'cm_Delete', locale_file => 'globals.xml'},
		transaction_id => {locale_const => 'Transaction ID', locale_file => 'manual_transaction.xml'},
		voucher_recharged => {locale_const => 'msg_Recharge_OK', locale_file => 'recharge.xml'},
		voice_calls => {locale_const => 'VOICE', locale_file => 'service_types.xml'},
		incoming_calls => {locale_const => 'VOICE_IN', locale_file => 'service_features.xml'},
		outgoing_calls => {locale_const => 'VOICE_OUT', locale_file => 'service_features.xml'},
		fraud_detection => {locale_const => 'FRAUD_DETECTION', locale_file => 'service_features.xml'},
		reject => {locale_const => 'action__reject', locale_file => 'call_proc.xml'},
		sip_ua => {locale_const => 'action__sip_ua', locale_file => 'call_proc.xml'},
		sip_ua__forward => {locale_const => 'action__sip_ua__forward', locale_file => 'call_proc.xml'},
		sip_ua__voicemail => {locale_const => 'action__sip_ua__voicemail', locale_file => 'call_proc.xml'},
		sip_ua__forward__voicemail => {locale_const => 'action__sip_ua__forward__voicemail', locale_file => 'call_proc.xml'},
		forward => {locale_const => 'action__forward', locale_file => 'call_proc.xml'},
		forward__voicemail => {locale_const => 'action__forward__voicemail', locale_file => 'call_proc.xml'},
		voicemail => {locale_const => 'action__voicemail', locale_file => 'call_proc.xml'},
		COUNTRIES => {locale_const => 'COUNTRIES', locale_file => 'locale.xml'},
		MOBILE_INTERNET => {locale_const => 'MOBILE_INTERNET', locale_file => 'locale.xml'},
		statistics => {locale_const => 'Statistics', locale_file => 'globals.xml'},
		TITLE_XDRS => {locale_const => 'sn_xDR_History', locale_file => 'cdr_browser.xml'},
		TITLE_CALCULATOR => {locale_const => 'RATE_CALCULATOR', locale_file => 'locale.xml'},
		user => {locale_const => 'User', locale_file => 'acl.xml'},
		more => {locale_const => 'the_more', locale_file => 'invoices.xml'},
		services => {locale_const => 'Services', locale_file => 'globals.xml'},
		old_password => {locale_const => 'Old password', locale_file => 'login.xml'},
		new_password => {locale_const => 'New Password', locale_file => 'login.xml'},
		retype_password => {locale_const => 'Retype New Password', locale_file => 'login.xml'},
		pay_now => {locale_const => 'Pay Now', locale_file => 'make_payment.xml'},
		CALL_FROM => {locale_const => 'CALL_FROM', locale_file => 'locale.xml'},
		CALL_TO => {locale_const => 'CALL_TO', locale_file => 'locale.xml'},
		rates => {locale_const => 'cm_Edit_Rates', locale_file => 'globals.xml'},
		LANDLINE => {locale_const => 'LANDLINE', locale_file => 'locale.xml'},
		mobile => {locale_const => 'mobile', locale_file => 'phone_book.xml'},
		select_destination => {locale_const => 'sn_Select_Destination', locale_file => 'destinations.xml'},
		search => {locale_const => 'Search', locale_file => 'tariff.xml'},
		RATE_NOT_FOUND => {locale_const => 'RATE_NOT_FOUND', locale_file => 'locale.xml'},
		payments => {locale_const => 'Payments/Refunds', locale_file => 'cdr_browser.xml'},
		credits => {locale_const => 'Credits / Adjustments', locale_file => 'cdr_browser.xml'},
		from => {locale_const => 'From', locale_file => 'cdr_browser.xml'},
		to => {locale_const => 'To', locale_file => 'cdr_browser.xml'},
		date_time => {locale_const => 'Date_Time', locale_file => 'cdr_browser.xml'},
		description => {locale_const => 'Description', locale_file => 'cdr_browser.xml'},
		charged_time => {locale_const => 'Charged time, min:sec', locale_file => 'cdr_browser.xml'},
		quantity => {locale_const => 'Quantity', locale_file => 'trace_call.xml'},
		connect_time => {locale_const => 'Connect Time', locale_file => 'trace_call.xml'},
		pager_of => {locale_const => 'pager_of', locale_file => 'globals.xml'},
		all => {locale_const => 'All', locale_file => 'cdr_browser.xml'},
		comment => {locale_const => 'Comment', locale_file => 'cdr_browser.xml'},
		fee_name => {locale_const => 'Fee Name', locale_file => 'cdr_browser.xml'},
		fee_type => {locale_const => 'Fee Type', locale_file => 'cdr_browser.xml'},
		total_charged => {locale_const => 'Total Charged', locale_file => 'cdr_browser.xml'},
		from_date => {locale_const => 'From Date', locale_file => 'cdr_browser.xml'},
		to_date => {locale_const => 'To Date', locale_file => 'cdr_browser.xml'},
		filter => {locale_const => 'Filter', locale_file => 'siplogview.xml'},
		ok => {locale_const => 'button_ok', locale_file => 'access_numbers.xml'},
		cancel => {locale_const => 'button_cancel', locale_file => 'access_numbers.xml'},
		now => {locale_const => 'Now', locale_file => 'cdr_browser.xml'},
		as_listed => {locale_const => 'FM_As_Listed', locale_file => 'follow_me.xml'},
		random => {locale_const => 'FM_Random', locale_file => 'follow_me.xml'},
		simultaneous => {locale_const => 'FM_Simultaneous', locale_file => 'follow_me.xml'},
		caller_number_and_name => {locale_const => "Caller_Number_and_Name", locale_file => 'follow_me.xml'},
		caller_number_and_forwarder_name => {locale_const => "Caller_Number_and_Forwarder_Name", locale_file => 'follow_me.xml'},
		forwarder_number_and_name => {locale_const => "Forwarder_Number_and_Name", locale_file => 'follow_me.xml'},
		follow_me_enabled => {locale_const => 'Follow Me Enabled', locale_file => 'account.xml'},
	};

	return $locale->{$constant} || undef;
}

sub _get_option_name
{
	my ($self,$attribute,$selection) = @_;
	my $output = undef;
	my $list = $self->_get_options($attribute);
	foreach(@$list)
	{
		if(defined $selection && $_->{value} eq $selection || $_->{sel})
		{
			$output = {name => $_->{name}, value => $_->{value}};
			last;
		}
	}
	return $output;
}

sub _get_options
{
	my ($self,$attribute) = @_;
	my $options_list = $self->_get('options_list');
	my $options = $options_list->{$attribute} || undef;
	if(!defined $options)
	{
		my $info = $self->_get('info');
		my $ph = $self->_get('ph');
		my $obj = $self->_get('obj');
		my $realm = $self->_get('realm');

		my $flag_options = $options_list->{flag_options} || [];
		if(!@$flag_options)
		{
			push @$flag_options, { value => '^', name => $self->_localize('customer_default') } if $realm eq 'Account';
			push @$flag_options, { value => 'N', name => $self->_localize('no') };
			push @$flag_options, { value => 'Y', name => $self->_localize('yes') };
			$options_list->{flag_options} = $flag_options;
		}

		if($self->_in_array(['favourite_numbers','emergency','paging','clip','call_processing','call_wait_limit',
			'um_enabled','call_barring','call_parking','first_login_greeting','group_pickup',
			'ecommerce_enabled','drm_enabled','ppm_enabled'],$attribute))
		{
			my $selection;
			my $properties = $self->_attribute_properties($attribute);
			if(defined $properties->{service})
			{
				$selection = $self->_get_service($attribute);
			}
			elsif(defined $properties->{service_flag})
			{
				$selection = $info->{service_flags_hash}->{$attribute};
			}
			else
			{
				$selection = $info->{$attribute};
			}

			$options = [
				{ value => 'N', name => $self->_localize('no') },
				{ value => 'Y', name => $self->_localize('yes') }
			];
			foreach (@$options) { $_->{sel} = ($selection eq $_->{value}) ? 1 : 0; }
		}
		elsif('i_time_zone' eq $attribute)
		{
			$options = $ph->timezones($info->{i_time_zone});
		}
		elsif($self->_in_array(['i_lang','iso_639_1'],$attribute))
		{
			$options = $ph->locale_languages($info->{$attribute});
		}
		elsif('i_billing_period' eq $attribute)
		{
			$options = $ph->billing_periods($info->{i_billing_period});
			foreach (@$options) { $_->{name} = $self->_localize(lc($_->{name})); }
		}
		elsif($self->_in_array(['send_invoices','send_statistics','follow_me_enabled','display_number_check','billing_model',
				'display_name_override','cli','clir','voice_pass_through','rtpp_level','default_action',
				'voice_location','allow_roaming'],$attribute))
		{
			my $selection = $info->{$attribute} || undef;
 			if($attribute eq 'send_invoices')
			{
				$options = [
					{ value => '', sel => '', name => $self->_localize('customer_default')},
					{ value => 'Y', sel => '', name => $self->_localize('yes')},
					{ value => 'N', sel => '', name => $self->_localize('no')}
				];
			}
			elsif('billing_model' eq $attribute)
			{
				$options = [
					{ value => -1, sel => '', name => $self->_localize('debit')},
					{ value => 0, sel => '', name => $self->_localize('voucher')},
					{ value => 1, sel => '', name => $self->_localize('credit')}
				];
			}
			elsif('allow_roaming' eq $attribute)
			{
				$options = [
					{ value => 'N', name => $self->_localize('mobility_stationary') },
					{ value => 'Y', name => $self->_localize('mobility_roaming') }
				];
				$selection = $info->{services}->{voice_location}->{allow_roaming}->{value};
			}
			elsif($attribute eq 'send_statistics')
			{
				$options = [
		            { value => '', sel => '', name => $self->_localize('default_cust_class')},
		            { value => 'F', sel => '', name => $self->_localize('full_stats')},
		            { value => 'S', sel => '', name => $self->_localize('summary_only')},
		            { value => 'N', sel => '', name => $self->_localize('do_not_send')}
				];
			}
			elsif($attribute eq 'follow_me_enabled')
			{
				$options = [
		            { value => 'N', sel => '', name => $self->_localize('no_forward')},
		            { value => 'Y', sel => '', name => $self->_localize('follow_me')},
		            { value => 'F', sel => '', name => $self->_localize('advanced_forward')},
		            { value => 'U', sel => '', name => $self->_localize('fw_sip_uri')},
		            { value => 'C', sel => '', name => $self->_localize('fw_cld')}
				];
			}
			elsif('display_number_check' eq $attribute)
			{
				$selection = $info->{services}->{cli}->{display_number_check}->{value};
				$options = [
					{ value => "N",  name => $self->_localize('never')},
					{ value => "A",  name => $self->_localize('Different_From_The_Used_Identity')},
					{ value => "Y",  name => $self->_localize('Ruled_Out_By_The_Identity_Constraint')},
					{ value => "D",  name => $self->_localize('always')}
				];
			}
			elsif('display_name_override' eq $attribute)
			{
				$selection = $info->{services}->{cli}->{display_name_override}->{value};
				$options = [
					{ value => "N",  name => $self->_localize('never')},
					{ value => "Y",  name => $self->_localize('always')}
				];
			}
			else
			{
				$selection = $info->{service_flags_hash}->{$attribute};
				if('voice_pass_through' eq $attribute)
				{
					$options = [
						{ value => '~', name => $self->_localize('product_default') },
						{ value => 'Y', name => $self->_localize('enabled') },
						{ value => 'N', name => $self->_localize('disabled') }
					];
				}
				elsif('phonebook' eq $attribute)
				{
					$options = [value => 'N', name => $self->_localize('disabled')];
					my $i = 0;
					while($i++ < 10) { push @$options, {value => $i, name => $i}; }
				}
				elsif($attribute eq 'voice_location')
				{
					$options = [
						{ value => '/', 'name' => $self->_localize('customer_default') },
						{ value => 'N', 'name' => $self->_localize('disabled') },
						{ value => 'Y', 'name' => $self->_localize('account_has_its_own') }
					];
				}
				elsif('cli' eq $attribute)
				{
					$options = [];
					push @$options, { value => '^', name => $self->_localize('customer_default') } if $realm eq 'Account';
					push @$options, { value => 'N', name => $self->_localize('never') };
					push @$options, { value => 'L', name => $self->_localize('Different_From_Account_ID_And_Aliases') };
					push @$options, { value => 'G', name => $self->_localize('Different_From_Customer_Accounts') };
					push @$options, { value => 'B', name => $self->_localize('Different_From_Accounts_In_The_Batch') };
					push @$options, { value => 'Y', name => $self->_localize('always') };
				}
				elsif('clir' eq $attribute)
				{
					$options = [];
					push @$options, { value => '^', name => $self->_localize('customer_default') } if $realm eq 'Account';
					push @$options, { value => 'N', name => $self->_localize('never') };
					push @$options, { value => 'Y', name => $self->_localize('always') };
					push @$options, { value => 'P', name => $self->_localize('automatic') };
				}
				elsif('rtpp_level' eq $attribute)
				{
					$options = [];
					push @$options, { value => '^', name => $self->_localize('customer_default') } if $realm eq 'Account';
					push @$options, { value => 'N', name => $self->_localize('use_default') };
					push @$options, { value => '0', name => $self->_localize('Direct') };
					push @$options, { value => '1', name => $self->_localize('Optimal') };
					push @$options, { value => '2', name => $self->_localize('On_NAT') };
					push @$options, { value => '3', name => $self->_localize('always') };
				}
				elsif('default_action' eq $attribute)
				{
					use Porta::CallProcessing;
					my $cp = new Porta::CallProcessing($ph);
					my $actions = $cp->get_actions({
						voicemail => $info->{um_enabled},
						forward   => $info->{follow_me_enabled},
						reject    => 'Y'
					});
					foreach my $action (@$actions) {
						push @$options, { name => $self->_localize($action->{name}), value => $action->{mask} };
					}
				}
			}

			foreach (@$options) { $_->{sel} = ($selection && $_->{value} && $selection eq $_->{value} || !($selection) && !$_->{value}) ? 1 : 0; }
		}
		elsif($self->_in_array(['i_vd_plan','i_distributor','i_routing_plan','i_payment_method','iso_3166_1_a2',
				'i_do_batch','i_rep','i_template','i_number_scope','i_customer_site','i_product'],$attribute))
		{
			my $list;
			my $name_key = 'name';
			my $value_key = $attribute;
			my $_value = $info->{$attribute} || '';
			if($self->_in_array(['i_vd_plan','i_distributor','i_rep','i_do_batch','i_template','i_number_scope','i_product'],$attribute))
			{
				use Porta::Customer;
				my $cust = new Porta::Customer($ph);
				my $cust_info = $cust->get($info->{i_customer});
				my $i_parent = $info->{i_parent} || 0;
				my $direct = $i_parent ? 0 : 1;
				my @_list;

				if($self->_in_array(['i_vd_plan','i_distributor','i_rep'],$attribute))
				{
					if($attribute eq 'i_vd_plan')
					{
						use Porta::DiscountPlan;
						my $DP = new Porta::DiscountPlan($ph);
						@_list = $DP->getList({
							from => 'All',
							iso_4217 => $info->{iso_4217},
							i_customer => $i_parent,
							direct => $direct,
							i_vd_plan => $info->{i_vd_plan}
						});
					}
					elsif('i_distributor' eq $attribute)
					{
						$value_key = 'i_customer';
						push(@_list,$cust->get_short_list($info->{i_distributor},{
							i_customer_type => CUSTOMER_DISTRIBUTOR,
							i_parent => $i_parent,
							hide_closed => 1,
							currency => $info->{iso_4217}
						}));
					}
					elsif('i_rep' eq $attribute)
					{
						use Porta::Representatives;
						my $R = new Porta::Representatives($ph);
						@_list = $R->getlist({
							from => 'All',
							i_customer => $cust_info->{i_customer_type} == CUSTOMER_WHOLESALE ? $i_parent : 0,
							direct => $direct,
							nohidden => 1,
							i_rep => $info->{i_rep}
						});
					}
					$list = $_list[0];
				}
				elsif('i_template' eq $attribute)
				{
					$list = [
						{i_template => '', sel => '', name => $self->_localize('default_cust_class')},
						{i_template => 0, sel => '', name => $self->_localize('no_invoice')}
					];
					my @_list = $cust->templates(($info->{i_template} || undef),{direct => $direct, i_customer => $i_parent});
					push(@$list,@{$_list[0]});
				}
				elsif('i_do_batch' eq $attribute)
				{
					use Porta::DID::OwnerBatch;

					my $do_batch = Porta::DID::OwnerBatch->new($ph);
					$list = $do_batch->get_list_simple({
				        'managed_by'  => $direct ? 'admin' : $i_parent,
				        'assigned_to' => $cust_info->{i_customer_type} == CUSTOMER_WHOLESALE ? 'reseller' : 'customer',
				        'iso_4217'    => $info->{'iso_4217'},
				    });
				}
				elsif('i_number_scope' eq $attribute)
				{
					use Porta::NumberScope;

					$list = [
						{i_number_scope => '', name => $self->_localize('use_default')},
						{i_number_scope => Porta::NumberScope->SCOPE_ENV, name => $self->_localize('Individual_For_Env')},
					];
					push(@$list, {i_number_scope => Porta::NumberScope->SCOPE_CUSTOMER, name => $self->_localize('Individual_For_Customer')}) if !$direct;
					push(@$list, {i_number_scope => Porta::NumberScope->SCOPE_RESELLER, name => $self->_localize('Individual_For_Reseller')});
				}
				elsif('i_product' eq $attribute)
				{
					use Porta::Product;

					my $p = new Porta::Product($ph);
					$options = $p->get_short_list(undef,{
						iso_4217          => $info->{i_product} || undef,
						i_customer        => $i_parent,
						include_direct    => 0,
						get_routing_plans => 1,
					});
				}
			}
			elsif('i_customer_site' eq $attribute)
			{
				use Porta::CustomerSite;

				my $site = Porta::CustomerSite->new({ 'ph' => $ph });
			    $list = $site->get_sites_list({
			        'i_env'      => $ph->{'i_env'},
			        'i_customer' => $info->{i_customer},
			    });
			}
			elsif($attribute eq 'i_routing_plan')
			{
				use Porta::RoutingPlans;

				my $RP = new Porta::RoutingPlans($ph);
				$list = $RP->getlist({ full_list => 1, simple_mode => 1 });
				$options = [{value => '', name => $self->_localize('All_Available_Routes'), sel => ($info->{i_routing_plan} ? '' : 1)}];
			}
			elsif($self->_in_array(['i_payment_method','iso_3166_1_a2'],$attribute))
			{
				use Porta::Payment;
				my $payment = Porta::Payment->new($ph);
				my $cc_info = $info->{i_credit_card} ? $payment->card_info($info->{i_credit_card}) : {};
				$_value = defined($cc_info->{$attribute}) ? $cc_info->{$attribute} : '';
				$value_key = 'value';

				if($attribute eq 'i_payment_method')
				{
					use Porta::Customer;
					my $cust = new Porta::Customer($ph);
					my $cust_info = $cust->get($info->{i_customer});
					$list = $payment->getAvailablePaymentMethods({
						i_payment_method	=> $cc_info->{i_payment_method},
						i_env				=> $info->{i_env},
						iso_4217			=> $info->{iso_4217},
						onlineOnly			=> 1,
						i_customer			=> $cust_info->{i_parent}
					});
				}
				elsif($attribute eq 'iso_3166_1_a2')
				{
					$list = $ph->countries();
				}
			}

			if($self->_in_array(['i_customer_site','i_vd_plan','i_distributor','i_payment_method',
					'iso_3166_1_a2','i_do_batch','i_rep'],$attribute))
			{
				$options = [{value => '', name => $self->_localize('none'), sel => ($_value ? '' : 1)}];
			}

			foreach my $row (@$list)
			{
				push(@$options,{
					name => $row->{$name_key},
					sel => (($_value eq $row->{$value_key}) ? 1 : 0),
					value => $row->{$value_key}
				});
			}
		}
		elsif($self->_in_array(['out_date_format','out_time_format','out_date_time_format','in_date_format','in_time_format'],$attribute))
		{
			my ($format) = $attribute =~ /^\w{2,3}_(.+)_format$/;
			my $all_formats = $self->_get_formats();
			my $formats = $all_formats->{$format};
			foreach my $option (@$formats)
			{
				push(@$options,{
					name => $option->{name},
					sel => (($option->{value} eq $info->{$attribute}) ? 1 : 0),
					value => $option->{value}
				});
			}
		}
		elsif($attribute eq 'i_moh')
		{
			use Porta::MOH;
			my $MOH = new Porta::MOH($ph);
			my $moh_value = ($realm ne 'Account' ? ($ph->getConfigValue('MOH','Default') || 0) : ($info->{i_moh} || ''));
			$options = [{value => undef, name => $self->_localize('none'), sel => ($moh_value ? '' : 1)}];
			push @$options, {name => $self->_localize('customer_default'), value => '', sel => (!defined $moh_value ? 1 : 0)} if $realm eq 'Account';
			my $moh_def_list = $MOH->getList({from => 'All', object => undef}) if $realm ne 'Account';
			my $moh_obj_list = $MOH->getList({
				from => 'All',
				object => ($realm eq 'Account' ? 'account' : 'customer'),
				i_object => ($realm eq 'Account' ? $info->{i_account} : $info->{i_customer})
			});
			if(defined $moh_def_list)
			{
				foreach my $i(@$moh_def_list)
				{
					my $sel = ($moh_value && $i->{i_moh} == $moh_value) ? 1 : 0;
					push @$options, {name => $i->{name}, value => $i->{i_moh}, sel => $sel};
				}
			}
			if($moh_obj_list)
			{
				foreach my $i(@$moh_obj_list)
				{
					my $sel = ($moh_value && $i->{i_moh} == $moh_value) ? 1 : 0;
					push @$options, {name => $i->{name}, value => $i->{i_moh}, sel => $sel};
				}
			}
		}
		elsif($attribute eq 'i_country_subdivision')
		{
			use Porta::Payment;
			my $payment = Porta::Payment->new($ph);
			my $cc_info = $info->{i_credit_card} ? $payment->card_info($info->{i_credit_card}) : {};
			my $_value = $cc_info->{i_country_subdivision} || '';
			my $states = $ph->subdivisions();
			foreach my $option (@$states)
			{
				$options->{$option->{iso_3166_1_a2}} = [] if (!defined($options->{$option->{iso_3166_1_a2}}));
				push(@{$options->{$option->{iso_3166_1_a2}}}, {name => $option->{name}, sel => (($option->{value} eq $_value) ? 1 : ''), value => $option->{value}});
			}
		}
		else
		{
			my $_options;
			my $_value;
			my $name_key = 'name';
			my $value_key = 'value';
			if($self->_in_array(['call_recording','endpoint_redirect','distinctive_ring_vpn','legal_intercept'],$attribute))
			{
				$_options = $flag_options;
				$_value = $info->{service_flags_hash}->{$attribute};
			}
			elsif($self->_in_array(['auto_record_redirected','auto_record_incoming','auto_record_outgoing'],$attribute))
			{
				my $auto_record_val = $info->{services}->{call_recording}->{auto_record}->{value} || 0;
				if('auto_record_redirected' eq $attribute)
				{
					$_value = ($auto_record_val & 4 ? 4 : 0);
					$_options = [{ value => '0', name => $self->_localize('no')},{ value => '4', name => $self->_localize('yes')}];
				}
				elsif('auto_record_incoming' eq $attribute)
				{
					$_value = ($auto_record_val & 2 ? 2 : 0);
					$_options = [{ value => '0', name => $self->_localize('no')},{ value => '2', name => $self->_localize('yes')}];
				}
				elsif('auto_record_outgoing' eq $attribute)
				{
					$_value = ($auto_record_val & 1 ? 1 : 0);
					$_options = [{ value => '0', name => $self->_localize('no')},{ value => '1', name => $self->_localize('yes')}];
				}
			}
			elsif('cli_batch' eq $attribute)
			{
				use Porta::DialRule;
				$value_key = 'i_dialing_rule';
				my $account_group = $info->{services}->{cli}->{account_group}->{value};
				$_value = $1 if (defined $account_group && $account_group =~ /^B(\d+)/);
				$_options = Porta::DialRule->get_arranged_rule_samples({
					'i_env' => $ph->{'i_env'},
					'get_examples' => 1,
				});
			}
			elsif($self->_in_array(['cli_trust_accept','cli_trust_supply'],$attribute))
			{
				my $cli_trust_v_map = {
					'^' => { accept => '^', supply => '^', },
					'F' => { accept => 'F', supply => 'Y', },
					'Y' => { accept => 'Y', supply => 'Y', },
					'N' => { accept => 'N', supply => 'N', },
					'f' => { accept => 'F', supply => 'N', },
					'y' => { accept => 'Y', supply => 'N', },
					'n' => { accept => 'N', supply => 'Y', }
		    	};
		    	if('cli_trust_accept' eq $attribute)
				{
				    $_options = [];
				    push @$_options, { value => '^', name => $self->_localize('customer_default') } if $realm eq 'Account';
				    push @$_options, { value => 'F', name => $self->_localize('Favor_forwarder') };
				    push @$_options, { value => 'Y', name => $self->_localize('Caller_only') };
				    push @$_options, { value => 'N', name => $self->_localize('none') };
				    $_value = $cli_trust_v_map->{$info->{service_flags_hash}->{cli_trust}}->{accept};
				}
				elsif('cli_trust_supply' eq $attribute)
				{
					$_options = $flag_options;
					$_value = $cli_trust_v_map->{$info->{service_flags_hash}->{cli_trust}}->{supply};
				}
			}
			elsif('voice_service_policy' eq $attribute)
			{
				use Porta::ServicePolicy;
				my $policy = new Porta::ServicePolicy({'ph' => $ph});
				$_options = $policy->get_policies_list({ i_service_type => 3 });
				push @$_options,{ i_service_policy => 'N', name => $self->_localize('use_default') };
				$_value = $info->{services}->{voice_service_policy}->{id}->{value} || 'N';
				$value_key = 'i_service_policy';
			}
			elsif('outgoing_access_number' eq $attribute)
			{
				use Porta::AccessNumbers;
				my $AccessNumbers = new Porta::AccessNumbers($ph);
				my ($acc_num_total,$acc_num_list) = $AccessNumbers->getlist({ i_env => $ph->{'i_env'} });
				$_options = $acc_num_list;
				$name_key = 'acc_num_name';
				$value_key = 'number';
				$_value = $info->{services}->{voice_pass_through}->{outgoing_access_number}->{value};
			}
			elsif('sequence' eq $attribute)
			{
				die "500" if $realm ne "Account";

				use Porta::FollowMe;

				my $followme = new Porta::FollowMe($ph);
				my $followme_info = $followme->get({i_account => $ph->{i_account}});
				$_value = $followme_info->{sequence};

				push @$_options, { value => 'Order', name => $self->_localize('as_listed') };
				push @$_options, { value => 'Random', name => $self->_localize('random') };
				push @$_options, { value => 'Simultaneous', name => $self->_localize('simultaneous') };
			}

			if($_options)
			{
				foreach my $j(@$_options)
				{
					my $sel = $_value && $_value eq $j->{$value_key} ? 1 : 0;
					push @$options, {value => $j->{$value_key}, name => $j->{$name_key}, sel => $sel};
				}
			}
		}

		if(defined $options)
		{
			$options_list->{$attribute} = $options;
			$self->_set('options_list',$options_list);
		}
	}

	return $options;
}

1;