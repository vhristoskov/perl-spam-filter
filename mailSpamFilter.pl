#!/usr/bin/perl -w
use strict;
use warnings;

use Mail::POP3Client;
use Email::MIME;

use File::Slurp;
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

sub extractMailWords{
    
    my ($mailBody, $mailWords) = @_;
    
    $mailWords = {} unless defined $mailWords;
    
    # remove punctuation
    $mailBody =~s/\W\s/ /g;
    
    # extract the words from the mail body
    while ( $mailBody =~ m/(\$?\b[\w|'|"|\-|.]+\b)/g ){
        
        unless ((length($1) < 3) || ($1 =~ /^[0-9]+$/)){
            $mailWords->{$1}++;
        }
    }
    
    return %{$mailWords};    
}



# Bayesian Filtering methods

my %hamWords;
my %spamWords;
my $numHamMessages;
my $numSpamMessages;

sub calcWordsProb{
    
    my @words = @_;
    my %probs;
        
    for my $word (@words){
        
        my $hamWordFreq = 2 * ( $hamWords{$word} || 0 );
        my $spamWordFreq = $spamWords{$word} || 0;
        
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

# pass as argument an array with the 15th most interesting words
sub calcMailProb{
    my @probs = @_;
    my $prod = reduce {$a * $b} @probs;
    
    return $prod / ($prod + reduce {$a * $b} map {1 - $_} @probs);
}


# Bayeson Utility methods
sub numTrainingMails{
    my ($trainingDir) = @_;
    
    my @files = <$trainingDir/*>;
    my $numOfFiles = scalar @files;
    
    return $numOfFiles;    
}

sub wordsStatisticInFile{
    
    
    # Another way to get the whole info from a file       
    #open(FH, "<$fileName") || die "Could not open file: $fileName".$!;   
    #{
    #    #if $/ is undef the filehandler will read whole info to the end of file
    #    local $/;
    #    $fileContent = <FH>;
    #}
    
    my ($fileName, $mailWordsHash) = @_;
    
    my $fileContent = '';
    $fileContent = read_file("$fileName");
    return extractMailWords($fileContent, $mailWordsHash);
}


sub getHamAndSpamStatistics{
    
    my ($hamDir, $spamDir) = @_;
    for( <'$hamDir/*'> ){
        wordsStatisticInFile($_, \%hamWords);
    }
    #print Dumper(\%hamWords)."\n";
    #print '##########################################################\n';
    
    for( <'$spamDir/*'> ){
        wordsStatisticInFile($_, \%spamWords);
    }
    ##print Dumper(\%spamWords)."\n";
    ##print '##########################################################\n';

}


MAIN:{

    my $configFile = "config.ini";
    tie my %iniConfig, 'Config::IniFiles', (-file => $configFile);
    
    # get number of the training emails
    my %trainingSetsDir = %{ $iniConfig{'TrainingSetDirs'} };

    $numHamMessages = numTrainingMails( $trainingSetsDir{hamDir} );
    $numSpamMessages = numTrainingMails( $trainingSetsDir{spamDir} );
    
    print "Number of ham training messages: $numHamMessages\n";
    print "Number of spam training messages: $numSpamMessages\n";
    
    getHamAndSpamStatistics($trainingSetsDir{hamDir}, $trainingSetsDir{spamDir} );
    
    
    #Fetch the emails from a server
    my %mailConfig = %{ $iniConfig{'MailHostConfig'} };  
    my (@unreadMails) = getEmails('username' => $mailConfig{username},
                                'password' => $mailConfig{password},
                                'mailhost' => $mailConfig{mailhost},
                                'port' => $mailConfig{port} );
    
     
     # extract and print the words from the mails
     my $messageCounter = 1;
     foreach (@unreadMails){
        my %mailWords = extractMailWords($_);
        
        my %wordsProb = calcWordsProb(keys %mailWords);
        
        #my @mostInterestingWords = sort { abs( 0.5 - $mailWords{$b}) <=> abs(0.5 - $mailWords{$a}) } values %wordsProb;
                
        my $spamProbability = calcMailProb(values %wordsProb);
        
        if($spamProbability >= 0.9){
            print "Message $messageCounter is SPAM!\n";
            
        }else{
            print "Message $messageCounter is HAM!\n";
        }
        
        $messageCounter++;
     
        #print '##########################################################';
        #print join "\n",
        #               map { qq/$_ -> $mailWords{$_}/ }
        #                    sort { $mailWords{$b} <=> $mailWords{$a} } keys %mailWords;
        
     }
 
}




