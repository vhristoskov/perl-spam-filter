#!/usr/bin/perl -w
use strict;
use warnings;

use Mail::POP3Client;
use Email::MIME;

use Config::IniFiles;
use XML::Simple;
use Data::Dumper;

use List::Util qw(min max reduce);


#use DBI;

my @emails;

sub getEmails{
    # Arguments: username, password, mailhost, port

    my %settings = @_;
    
    my $popMailServer = Mail::POP3Client->new(USER => $settings{'username'},
                             PASSWORD => $settings{'password'},
                             HOST => $settings{'mailhost'},
                             PORT => $settings{'port'},
                             USESSL => 1,
                             DEBUG => 0);
    
    die 'ERROR: Connection failed!\n' if ( $popMailServer->Count() == -1 );

    my $is_alive = $popMailServer->Alive();
    if( $is_alive == 0){
        print "Error: disconnected!\n";
        $popMailServer->Login();
    }
    else{
        print "You are currently connected to: ".$popMailServer->Host()."\n";
    }
    
    print "You have ".$popMailServer->Count()." new message(s)\n";
    
    for (my $i = 1; $i <= $popMailServer->Count(); $i++){
            
        my $message = $popMailServer->HeadAndBody($i);
        
    #    Parse the Mail to get the body
        my $parsedMsg = Email::MIME->new($message); 
        my @parts = $parsedMsg->parts();
        push @emails,  $parts[0]->body();
    }
    $popMailServer->close();
    
    return @emails;
}

sub extractMailWords($){
    
    my ($mailBody) = @_;
    my %mailWords;
    
    # remove punctuation
    $mailBody =~s/\W\s/ /g;
    
    # extract the words from the mail body
    while ( $mailBody =~ m/(\$?\b[\w|'|"|\-|.]+\b)/g ){
        
        unless (length($1) < 3){
            $mailWords{$1}++;
        }
    }
    
    return %mailWords;    
}



# Bayesian Filtering methods

my %hamWords;
my %spamWords;
my %numHamMessages;
my %numSpamMessages;

# TODO: To pass as argument keys of the %ham and %spam
sub calcWordsProb{
    
    my @words = @_;
    my %probs
        
    for my $word (@words){
        
        my $hamWordFreq = 2 * ( $hamWordFreq{$word} || 0 );
        my $spamWordFreq = $spamWordFreq{$word} || 0;
        
        unless ($hamWordFreq + $spamWordFreq < 5){
            $probs{$word} = max(0.01,
                                min (0.99,
                                      min (1, $spamWordFreq / $numSpamMessages) /
                                            ( min(1, $hamWordFreq / $numHamMessages) +
                                              min(1, $spamWordFreq / $numSpamMessages))
                                    )
                            )
        } 
    }

    return %probs;   
}

sub calcMailProb{
    my @probs = @_;
    my $prod = reduce {$a * $b} @probs;
    
    return $prod / ($prod + reduce {$a * $b} map {1 - $_} @probs);
}

#sub dbManipulation{
#    my $driver = 'mysql';
#    my $database = 'PERLTEST';
#    my $dbSourceName = "DBI:$driver:$database";
#    my $userId = 'perl.test';
#    my $password = 'perl.test';
#    
#    my $dbh = DBI->connect($dbSourceName, $userId, $password)
#                or die "Couldn't connect to database: ". DBI->errstr;
#    
#    my $sth = $dbh->prepare_cached('SELECT * FROM People')
#                    or die "Couldn't prepare statement: ". $dbh->errstr;
#                    
#    $sth->execute
#            or die "Couldn't execute statement: ". $sth->errstr;
#    my @personData;
#    
#    while( @personData = $sth->fetchrow_array()){
#        print "\t$personData[0]: $personData[1] $personData[2] $personData[3]\n"; 
#    }
#    
#    $sth->finish;
#    print "\n";
#    
#    $dbh->disconnect; 
#}


my $configFile = "config.ini";
tie my %iniConfig, 'Config::IniFiles', (-file => $configFile);

my %mailConfig = %{ $iniConfig{'MailHostConfig'} };

my (@unreadMails) = getEmails('username' => $mailConfig{username},
                            'password' => $mailConfig{password},
                            'mailhost' => $mailConfig{mailhost},
                            'port' => $mailConfig{port} );

 
 foreach (@unreadMails){
    my %mailWords = extractMailWords($_);
 
    print join "\n",
                   map { qq/$_ -> $mailWords{$_}/ }
                        sort { $mailWords{$b} <=> $mailWords{$a} } keys %mailWords;
    
 }
 
 

#dbManipulation;




