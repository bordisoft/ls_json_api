package JsonApi::Telisim;

use lib $ENV{'PORTAHOME_WEB'}.'/apache/ls_json_api';
use parent 'JsonApi::Account';

sub new
{
	my $self = shift;
	my $ph = shift;
	$ENV{JSON_Api_Realm} = 'Account';

	return $self->SUPER::new($ph);
}

sub get_cdrs
{
	my ($self,$args) = @_;

	die "400 no arguments to get cdrs" if ref($args) ne "HASH" || !%$args;

	if(defined $args->{voice_calls} || defined $args->{all})
	{
		my $output = {};
		my @services = defined $args->{all} ? qw(voice_calls subscriptions payments credits messaging faxes) : keys %$args;
		foreach(@services)
		{
			my $cdrs = undef;
			my $_args = defined $args->{all} ? $args->{all} : $args->{$_};
			if('voice_calls' eq $_)
			{
				$cdrs->{voice_calls} = $self->_process_telisim_cdrs($_args);
			}
			else
			{
				$cdrs = $self->SUPER::get_cdrs({$_ => $_args});
			}
			$output->{$_} = $cdrs->{$_};
		}

		return $output;
	}

	return $self->SUPER::get_cdrs($args);
}

sub _process_telisim_cdrs
{
	use Porta::SQL;
	use Porta::Date;

	my ($self,$args) = @_;
	my $info = $self->_get('info');
	my $ph = $self->_get('ph');
	my $from = $args->{from} || 0;
	my $limit = $args->{limit} || 'all';
	my $from_date = undef;
	my $to_date = undef;

	$from_date = $self->_format_datetime("default",$args->{from_date},$ph->{TZ},"UTC") if defined $args->{from_date};
	$to_date = $self->_format_datetime("default",$args->{to_date},$ph->{TZ},"UTC") if defined $args->{to_date};

	if(!defined $from_date || !defined $to_date)
	{
		if(!defined $from_date)
		{
			my $date = Porta::Date->new();
			$date->add_interval('MONTH', '-', 1);
			$from_date = $date->asISO("UTC");
		}
		if(!defined $to_date)
		{
			my $date = Porta::Date->new();
			$date->add_interval('DAY', '+', 3);
			$to_date = $date->asISO("UTC");
		}
	}
	$limit = 200 if ('all' eq $limit || $limit > 200);

	my $output = {
		list => [],
		total_amount => 0,
		total_count => 0,
		subtotal_amount => 0,
		subtotal_count => 0,
		from => $from,
		limit => $limit
	};
	my $sql_body = " IFNULL(x.h323_incoming_conf_id,x.h323_conf_id) as h323
		FROM CDR_Accounts x
		INNER JOIN Destinations d USING(i_dest)
		LEFT JOIN Countries c USING(iso_3166_1_a2)
		LEFT JOIN Accessibility a USING(i_accessibility)
		WHERE x.i_env = $info->{i_env}
		AND x.i_service = 3
		AND x.i_account = \"$info->{i_account}\"
		AND x.bill_time >= \"$from_date\"
		AND x.bill_time <= \"$to_date\"
		GROUP BY h323";
	my $sql_total = "SELECT SQL_NO_CACHE COUNT(t.h323) as total_count FROM(SELECT".$sql_body.") as t";
	my $st = undef;
	eval { $st = Porta::SQL->prepareNexecute({ sql => $sql_total }, 'porta-billing-slave');
	1 } or die "500 sql error";
	if($st) { while (my $data = $st->fetchrow_hashref) { $output->{total_count} = $data->{total_count}; } }

	if($output->{total_count})
	{
		use POSIX;
		use Date::Parse;

		my $sql_list = "SELECT SQL_NO_CACHE GROUP_CONCAT(x.bill_time SEPARATOR \"|\") as bill_time,
			GROUP_CONCAT(x.connect_time SEPARATOR \"|\") as connect_time,
			GROUP_CONCAT(x.disconnect_time SEPARATOR \"|\") as disconnect_time,
			GROUP_CONCAT(x.charged_quantity SEPARATOR \"|\") as charged_quantity,
			GROUP_CONCAT(x.CLI SEPARATOR \"|\") as cli,
			GROUP_CONCAT(x.CLD SEPARATOR \"|\") as cld,
			GROUP_CONCAT(x.charged_amount SEPARATOR \"|\") as charged_amount,
			GROUP_CONCAT(c.name SEPARATOR \"|\") as country,
			GROUP_CONCAT(d.description SEPARATOR \"|\") as description,
			GROUP_CONCAT(a.CLD SEPARATOR \"|\") as accessibility,
			$sql_body ORDER BY x.bill_time DESC LIMIT $limit OFFSET $from";
		$st = undef;
		eval { $st = Porta::SQL->prepareNexecute({ sql => $sql_list }, 'porta-billing-slave');
		1 } or die "500 sql error";
		if($st) { while (my $data = $st->fetchrow_hashref) {
			if(index($data->{bill_time},"|") != -1)
			{
				my @connect_time = split(/\|/,$data->{connect_time});
				my $LEGA = str2time($connect_time[0]) < str2time($connect_time[1]) ? 0 : 1;
				my $LEGB = $LEGA == 1 ? 0 : 1;
				my $cdrs = {};
				foreach(keys %$data)
				{
					if("h323" ne $_)
					{
						my @values = split(/\|/,$data->{$_});
						$cdrs->{LEGA}->{$_} = $values[$LEGA];
						$cdrs->{LEGB}->{$_} = $values[$LEGB];
					}
				}
				$data = {
				    bill_time => $cdrs->{LEGA}->{bill_time},
				    charged_quantity => $cdrs->{LEGA}->{charged_quantity},
				    charged_amount => $cdrs->{LEGA}->{charged_amount}+$cdrs->{LEGB}->{charged_amount},
				    cld => $cdrs->{LEGB}->{cld},
				    cli => $cdrs->{LEGB}->{cli},
				    country => $cdrs->{LEGB}->{country},
				    description => $cdrs->{LEGB}->{description},
				    disconnect_time => $cdrs->{LEGA}->{disconnect_time},
				    accessibility => "LEGA+LEGB"
				};
			}
			my $connect_date = $self->_format_datetime($ph->{'out_date_format'},$data->{bill_time},"UTC");
			my $connect_time = $self->_format_datetime($ph->{'out_time_format'},$data->{bill_time},"UTC");
			my $duration = floor($data->{charged_quantity}/60).':'.($data->{charged_quantity}%60 < 10 ? '0'.$data->{charged_quantity}%60 : $data->{charged_quantity}%60);
			my $row = {
				connect_date => $connect_date,
				connect_time => $connect_time,
				unix_connect_time => $self->_format_datetime('unixtime',$data->{bill_time}),
				duration => $duration,
				account_id => $info->{id},
				cli => $data->{cli},
				cld => $data->{cld},
				amount => $data->{charged_amount},
				description => $data->{description},
				country => $data->{country},
				accessibility => $data->{accessibility} || "ALL"
			};
			push @{$output->{list}}, $row;
			$output->{subtotal_amount} += $data->{charged_amount};
			++$output->{subtotal_count};
		} }
	}

	return $output;
}

sub calculate_rates
{
	my ($self,$args) = @_;

	die "400 no arguments to calculate rates" if (ref($args) ne "HASH" || !$args->{iso_3166_1_a2_from} || !$args->{iso_3166_1_a2_to});

	my $from_destinations = $self->_search_destinations({search_by => "iso_3166_1_a2", pattern => $args->{iso_3166_1_a2_from}});
	my $to_destinations;
	if($args->{iso_3166_1_a2_from} ne $args->{iso_3166_1_a2_to})
	{
		$to_destinations = $self->_search_destinations({search_by => "iso_3166_1_a2", pattern => $args->{iso_3166_1_a2_to}});
	}
	else { $to_destinations = $from_destinations; }

	die "400 incorrect destinations" if (!$from_destinations || !$to_destinations);

	use Porta::SQL;

	my $info = $self->_get("info");
	my $from_clause = '';
	my $to_clause = '';
	my $mobnet_clause = '';
	my $sql;
	my $st;

	my $patterns = {};
	foreach(keys %$from_destinations)
	{
		if($from_destinations->{$_}->{description} eq "Proper")
		{
			$from_clause = " d.destination LIKE \"".$from_destinations->{$_}->{destination}."%\"";
			$patterns = {};
			last;
		}
		else
		{
			my $dest = substr($from_destinations->{$_}->{destination},0,2);
			$patterns->{$dest} = "d.destination LIKE \"$dest%\"";
		}
	}
	if(!$from_clause && %$patterns)
	{
		foreach(keys %$patterns)
		{
			$from_clause .= ("" eq $from_clause ? "" : " OR ").$patterns->{$_};
		}
		$from_clause = " (".$from_clause.")";
	}
	if($args->{iso_3166_1_a2_from} ne $args->{iso_3166_1_a2_to})
	{
		$patterns = {};
		foreach(keys %$to_destinations)
		{
			if($to_destinations->{$_}->{description} eq "Proper")
			{
				$to_clause = " d.destination LIKE \"".$to_destinations->{$_}->{destination}."%\"";
				$patterns = {};
				last;
			}
			else
			{
				my $dest = substr($to_destinations->{$_}->{destination},0,2);
				$patterns->{$dest} = "d.destination LIKE \"$dest%\"";
			}
		}
		if(!$to_clause && %$patterns)
		{
			foreach(keys %$patterns)
			{
				$to_clause .= ("" eq $to_clause ? "" : " OR ").$patterns->{$_};
			}
			$to_clause = " (".$to_clause.")";
		}
	}
	else { $to_clause = $from_clause; }

	return {notice => $self->_localize("RATE_NOT_FOUND")} if (!$to_clause || !$from_clause);

	$sql = "SELECT CONCAT(mcc,mnc) as prefix FROM `Litespan`.TeliSIM_MCC_MNC WHERE PLMNO LIKE \"$args->{iso_3166_1_a2_from}%\" OR description LIKE \"$args->{iso_3166_1_a2_from}%\"";
	$st = undef;
	eval { $st = Porta::SQL->prepareNexecute({ sql => $sql }, 'porta-billing-slave');
	1 } or die "500 sql error";
	if($st) { while (my $data = $st->fetchrow_hashref) { $mobnet_clause .= ("" eq $mobnet_clause ? "" : ",")."\"$data->{prefix}\""; } }
	$mobnet_clause = "" ne $mobnet_clause ? " d.destination IN (".$mobnet_clause.")" : $mobnet_clause;

	my $clauses = {};
	$clauses->{($self->_in_array(["MX","US"],$args->{iso_3166_1_a2_from}) ? LEGAUS : LEGA)} = $clauses->{MO} = {clause => $from_clause, iso_3166_1_a2 => $args->{iso_3166_1_a2_from}};
	$clauses->{($self->_in_array(["MX","US"],$args->{iso_3166_1_a2_to}) ? LEGBUS : LEGB)} = $clauses->{MT} = {clause => $to_clause, iso_3166_1_a2 => $args->{iso_3166_1_a2_to}};
	$clauses->{DATA} = {clause => $mobnet_clause};

	$sql = "SELECT IFNULL(a.i_tariff,r.i_tariff) as i_tariff, IFNULL(a.CLD,s.name) as access_code
		FROM `porta-billing`.Accessibility AS a
		LEFT JOIN `porta-billing`.Service_Types AS s ON s.i_service_type = a.i_service_type
		LEFT JOIN `porta-billing`.Accessibility_Routing_Tariff AS r ON r.i_accessibility = a.i_accessibility
		WHERE a.i_product = $info->{i_product}
		AND (CLD IN (\"LEGA\",\"LEGB\",\"LEGAUS\",\"LEGBUS\",\"MT\",\"MO\") OR s.name = \"DATA\")";
	$st = undef;
	my $tariffs = [];
	eval { $st = Porta::SQL->prepareNexecute({ sql => $sql }, 'porta-billing-slave');
	1 } or die "500 sql error";
	if($st) { while (my $data = $st->fetchrow_hashref) { push @$tariffs, $data; } }

	return {notice => $self->_localize("RATE_NOT_FOUND")} if (!@$tariffs);

	my $output = {};
	foreach(@$tariffs)
	{
		foreach my $key(keys %$clauses)
		{
			if($key eq $_->{access_code} && $clauses->{$key}->{clause})
			{
				if($key eq "DATA")
				{
					my $clause = $clauses->{$key}->{clause};
					$sql = "SELECT MAX(r.op_price_n) as price_max, MIN(r.op_price_n) as price_min
						FROM `porta-billing`.Rates AS r
						JOIN `porta-billing`.Destinations AS d ON d.i_dest = r.i_dest
						WHERE r.i_tariff = $_->{i_tariff}
						AND $clause
						AND r.active = \"Y\"
						AND r.hidden = \"N\"
						AND r.discontinued = \"N\"
						AND r.forbidden = \"N\"
						AND r.effective_from < NOW()
						AND (r.inactive_from IS NULL OR r.inactive_from > NOW())";
					$st = undef;
					eval { $st = Porta::SQL->prepareNexecute({ sql => $sql }, 'porta-billing-slave');
					1 } or die "500 sql error";
					if($st) { while (my $data = $st->fetchrow_hashref) { $output->{$key} = {price_max => $data->{price_max}, price_min => $data->{price_min}}; } }
				}
				else
				{
					my $clause = $clauses->{$key}->{clause};
					my $iso_3166_1_a2 = $clauses->{$key}->{iso_3166_1_a2};
					$sql = "SELECT IF(l.type = \"M\",\"mobile\",IF(d.description LIKE \"%mobile%\",\"mobile\",IF(d.description LIKE \"%celular%\",\"mobile\",\"landline\"))) as direction,
							MAX(r.op_price_n) as price_max,
							MIN(r.op_price_n) as price_min
						FROM `porta-billing`.Rates AS r
						JOIN `porta-billing`.Destinations AS d ON d.i_dest = r.i_dest
						LEFT JOIN `Litespan`.TeliSIM_Mobile_Prefixes as l on d.destination = l.prefix
						WHERE r.i_tariff = $_->{i_tariff}
						AND $clause
						AND (l.PLMNO LIKE \"$iso_3166_1_a2%\" OR d.iso_3166_1_a2 = \"$iso_3166_1_a2\")
						AND r.active = \"Y\"
						AND r.hidden = \"N\"
						AND r.discontinued = \"N\"
						AND r.forbidden = \"N\"
						AND r.effective_from < NOW()
						AND (r.inactive_from IS NULL OR r.inactive_from > NOW())
						GROUP BY direction";
					$st = undef;
					eval { $st = Porta::SQL->prepareNexecute({ sql => $sql }, 'porta-billing-slave');
					1 } or die "500 sql error";
					if($st) { while (my $data = $st->fetchrow_hashref) {
						$key = index($key,"US") == -1 ? $key : substr($key,0,index($key,"US"));
						$output->{$key}->{$data->{direction}} = {price_max => $data->{price_max}, price_min => $data->{price_min}};
					} }
				}
			}
		}
	}

	my $calculated = {
		vc_landline => {
			price_max => defined $output->{LEGA}->{mobile}->{price_max} && defined $output->{LEGB}->{landline}->{price_max}
				? $self->_format_price($output->{LEGA}->{mobile}->{price_max}+$output->{LEGB}->{landline}->{price_max})."/min"
				: $self->_localize("none"),
			price_min => defined $output->{LEGA}->{mobile}->{price_min} && defined $output->{LEGB}->{landline}->{price_min}
				? $self->_format_price($output->{LEGA}->{mobile}->{price_min}+$output->{LEGB}->{landline}->{price_min})."/min"
				: $self->_localize("none"),
		},
		vc_mobile => {
			price_max => defined $output->{LEGA}->{mobile}->{price_max} && defined $output->{LEGB}->{mobile}->{price_max}
				? $self->_format_price($output->{LEGA}->{mobile}->{price_max}+$output->{LEGB}->{mobile}->{price_max})."/min"
				: $self->_localize("none"),
			price_min => defined $output->{LEGA}->{mobile}->{price_min} && defined $output->{LEGB}->{mobile}->{price_min}
				? $self->_format_price($output->{LEGA}->{mobile}->{price_min}+$output->{LEGB}->{mobile}->{price_min})."/min"
				: $self->_localize("none"),
		},
		sms => {
			price_max => defined $output->{MO}->{mobile}->{price_max} && defined $output->{MT}->{mobile}->{price_max}
				? $self->_format_price($output->{MO}->{mobile}->{price_max}+$output->{MT}->{mobile}->{price_max})
				: $self->_localize("none"),
			price_min => defined $output->{MO}->{mobile}->{price_min} && defined $output->{MT}->{mobile}->{price_min}
				? $self->_format_price($output->{MO}->{mobile}->{price_min}+$output->{MT}->{mobile}->{price_min})
				: $self->_localize("none"),
		},
		mobile_internet => {
			price_max => defined $output->{DATA}->{price_max}
				? $self->_format_price($output->{DATA}->{price_max})
				: $self->_localize("none"),
			price_min => defined $output->{DATA}->{price_min}
				? $self->_format_price($output->{DATA}->{price_min})
				: $self->_localize("none"),
		},
	};

	return $calculated;
}

sub get_sim_location
{
	my $self = shift;
	my $lu = $self->get_custom_fields({fields => ["SIM_LU"]});

	return "NOT APPLICABLE" if ref($lu) ne "HASH" || !$lu->{SIM_LU}->{value};

	my $mcc = substr($lu->{SIM_LU}->{value},0,index($lu->{SIM_LU}->{value},"|"));
	my $mnc = substr($lu->{SIM_LU}->{value},index($lu->{SIM_LU}->{value},"|")+1);
	my $sql = "SELECT country_code FROM `Litespan`.TeliSIM_MCC_MNC WHERE mcc=\"$mcc\" AND mnc=\"$mnc\"";
	my $st = undef;
	my $country_code = undef;
	eval { $st = Porta::SQL->prepareNexecute({ sql => $sql }, 'porta-billing-slave');
	1 } or die "500 sql error";
	if($st) { while (my $data = $st->fetchrow_hashref) { $country_code = $data->{country_code}; } }

	return "NOT APPLICABLE" if !$country_code;

	$country_code =~ s/[^0-9+]//g;
	my $dest_info = $self->_search_destinations({search_by => "destination", pattern => $country_code});

	return ref($dest_info) eq "HASH" && %$dest_info ? $dest_info->{(keys %$dest_info)[0]}->{country} : "NOT APPLICABLE";
}

1;