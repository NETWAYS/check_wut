#!/usr/bin/perl -w
# $Id: 10defbb72f3464bf143e1fea48f5e9ed18c0f06b $

=pod

=head1 COPYRIGHT

 
This software is Copyright (c) 2011 NETWAYS GmbH, William Preston
                               <support@netways.de>

(Except where explicitly superseded by other copyright notices)

=head1 LICENSE

This work is made available to you under the terms of Version 2 of
the GNU General Public License. A copy of that license should have
been provided with this software, but in any event can be snarfed
from http://www.fsf.org.

This work is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 or visit their web page on the internet at
http://www.fsf.org.


CONTRIBUTION SUBMISSION POLICY:

(The following paragraph is not intended to limit the rights granted
to you to modify and distribute this software under the terms of
the GNU General Public License and is only of importance to you if
you choose to contribute your changes and enhancements to the
community by submitting them to NETWAYS GmbH.)

By intentionally submitting any modifications, corrections or
derivatives to this work, or any other work intended for use with
this Software, to NETWAYS GmbH, you confirm that
you are the copyright holder for those contributions and you grant
NETWAYS GmbH a nonexclusive, worldwide, irrevocable,
royalty-free, perpetual, license to use, copy, create derivative
works based on those contributions, and sublicense and distribute
those contributions and any derivatives thereof.

Nagios and the Nagios logo are registered trademarks of Ethan Galstad.

=head1 NAME

check_wut_health

=head1 SYNOPSIS

Retrieves the status of a wut and converts the resulting error code

=head1 OPTIONS

check_wut_health [options] <hostname> <SNMP community>

=over

=item   B<--warning>

warning levels (comma separated) - default 20

=item   B<--critical>

critical levels (comma separated) - default 40

=item   B<--unit>

sensor measuring units (comma separated) - default C

=item   B<--timeout>

how long to wait for the reply (default 30s)

=item   B<--type>

device type (as a number).
Default is 0 (autodetect)

=back

=head1 DESCRIPTION

This plugin checks the status of a wut Appliance using SNMP

It doesn't require the MIB (the OID is
hardcoded into the script)

If you have multiple sensors you can specify the warning, critical
and unit options as a comma-separated list.

=cut

use Getopt::Long;
use Pod::Usage;
%ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
%ERRORSREV=reverse %ERRORS;
use Net::SNMP;

sub nagexit($$);

my $warning = 20;
my $critical = 40;
my $unit = "C";
my $tout = 15;
my $version;
my $exitval = 0;
my $type = 0;

# check the command line options
GetOptions('help|?' => \$help,
	   'V|version' => \$version,
           't|timeout=i' => \$tout,
           'type=i' => \$type,
           'u|unit=s' => \$unit,
           'w|warn|warning=s' => \$warning,
           'c|crit|critical=s' => \$critical);

if ($#ARGV!=1) {$help=1;} # wrong number of command line options
# pod2usage( -verbose => 99, -sections => "NAME|COPYRIGHT|SYNOPSIS|OPTIONS") if $help;
pod2usage(1) if $help;

my $host = shift;
my $community = shift;
my $wtWebio = '.1.3.6.1.4.1.5040.1.2';


$SIG{'ALRM'} = sub { nagexit('CRITICAL', "Timeout trying to reach device $host") };

alarm($tout);

my ($session, $error) = Net::SNMP->session(
	-hostname	=>	$host,
	-community	=>	$community);
if (!defined($session)) { nagexit('CRITICAL', "Failed to reach device $host") };

my $result;

if ($type == 0) {
	# autodetect device
	

	$result = $session->get_next_request(
	-varbindlist		=>	[$wtWebio]);

	nagexit('UNKNOWN', "Failed to query device") unless (defined($result));

	my $device = (keys(%$result))[0];
	$device =~ s/$wtWebio\.(\d*).*/$1/;
	
	nagexit('UNKNOWN', "Failed to detect device, try setting it manually") unless (defined($device) and ($device > 0));
	$type = $device;
		
		
}

my %OIDS = (	wtWebioSensors.0	=>	$wtWebio.'.'.$type.'.1.1.0',
		wtWebioDeviceName.0	=>	$wtWebio.'.'.$type.'.3.1.1.1.0',
		wtWebioDeviceLocation.0	=>	$wtWebio.'.'.$type.'.3.1.1.3.0',
		wtWebioBinaryTempValue	=>	$wtWebio.'.'.$type.'.1.4.1.1',
		wtWebioPort		=>	$wtWebio.'.'.$type.'.3.2.1.1',
		wtWebioPortName		=>	$wtWebio.'.'.$type.'.3.2.1.1.1',
		wtWebioPortText		=>	$wtWebio.'.'.$type.'.3.2.1.1.2');


$result = $session->get_request(
	-varbindlist	=>	[$OIDS{wtWebioSensors.0}, $OIDS{wtWebioDeviceName.0}, $OIDS{wtWebioDeviceLocation.0}]);
if (!defined($result)) { nagexit('CRITICAL', "Failed to query device $host") };

my $number = $result->{$OIDS{wtWebioSensors.0}};
my $outstr = $result->{$OIDS{wtWebioDeviceName.0}};
$outstr .= " in ". $result->{$OIDS{wtWebioDeviceLocation.0}} if ($result->{$OIDS{wtWebioDeviceLocation.0}} ne "");
$outstr =~ s/\r\n/, /g;

my $sensor = $session->get_table(
	-baseoid	=>	$OIDS{wtWebioPort});
if (!defined($sensor)) { nagexit('CRITICAL', "Failed to query device $host") };

my $temp = $session->get_table(
	-baseoid	=>	$OIDS{wtWebioBinaryTempValue});
if (!defined($temp)) { nagexit('CRITICAL', "Failed to query device $host") };

my @results;
my @perfdata;

# create arrays for the thresholds and units
my @warning = split(/,/, $warning);
while ($#warning < ($number - 1)) {
	push @warning, $warning;
}
my @critical = split(/,/, $critical);
while ($#critical < ($number - 1)) {
	push @critical, $critical;
}
my @unit = split(/,/, $unit);
while ($#unit < ($number - 1)) {
	push @unit, $unit;
}

for ($i = 0; $i < $number; $i++) {
	my $value = (($temp->{$OIDS{wtWebioBinaryTempValue}.".".($i + 1)})/10);
	my $status = 0;
	if ($value > $critical[$i]) {
		$status = 2;
		$exitval = 2;
	} elsif ($value > $warning[$i]) {
		$status = 1;	
		$exitval = 1 if ($exitval < 2);
	}

	my $valunit = $unit[$i];
	push @results, "[".$ERRORSREV{$status}."] ".$sensor->{$OIDS{wtWebioPortName}.".".($i + 1)}." (".$sensor->{$OIDS{wtWebioPortText}.".".($i + 1)}.") ist ".$value.$valunit;
	push @perfdata, "sensor_".($i + 1)."=".$value.$valunit.";".$warning[$i].";".$critical[$i];
}


foreach my $line (@results) {
	# multiline if more than 1 sensor
	if ($#results > 0) {
		$outstr.= "\n";
	}
	$outstr .= $line;
}
$outstr.= "|";

foreach my $perfdata (@perfdata) {
	$outstr.= " ".$perfdata;
}

nagexit($ERRORSREV{$exitval}, $outstr);

sub nagexit($$) {
	my $errlevel = shift;
	my $string = shift;

	if (defined($session)) { $session->close };

	print "$errlevel: $string\n";
	exit $ERRORS{$errlevel};
}
