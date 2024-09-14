#!/usr/bin/perl

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Path qw(make_path remove_tree);
use Getopt::Std;
use Text::CSV;

$main::VERSION = '0.1';

$Getopt::Std::STANDARD_HELP_VERSION = 1;
my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
open my $fh, ">:encoding(utf8)", "line_modifications.csv" or die "line_modifications.csv: $!";
$csv->say($fh, ["File", "Modification Count", "Status", "Last Line Number", "Last Content"]);

sub main::HELP_MESSAGE {
    my ($fh) = @_;
    print $fh qq{
Usage: $0 [options ...] [input file ...]
-c  Output in "compressed" format: commit, followed by birthday of deaths
-d  Report the LoC delta
-D opts  Debug as specified by the letters in opts
    C Show commit set changes
    D Show diff headers
    E Show diff extended headers
    H Show each commit SHA, timestamp header
    L Show LoC change processing
    P Show push to change set operations
    R Reconstruct the repository contents from its log
    @ Show range headers
    S Show results of splicing operations
    u Run unit tests
-e SHA  End processing after the specified (full) SHA commit hash
-E  Redirect (debugging) output to stderr
-g file  Create a growth file with line count of live lines at every commit
-h  Print usage information and exit
-l  Associate with each line details about its composition
-q  Quiet; do not output commit and timestamp on normal processing
-s  Report only changes in source code files (based on their suffix)
-t  Show tokens with lifetime
};
}

our($opt_c, $opt_d, $opt_D, $opt_e, $opt_E, $opt_g, $opt_h, $opt_l, $opt_q, $opt_s, $opt_t);

if (!getopts('cdD:e:Eg:hlqst')) {
    main::HELP_MESSAGE(*STDERR);
    exit 1;
}

if (defined($opt_h)) {
    HELP_MESSAGE(\*STDOUT);
    exit(0);
}

open(STDOUT, ">&STDERR") if (defined($opt_E));

my %line_modifications;
my $growth_file;

my $loc = 0;
my $prev_loc = 0;

open($growth_file, '>', $opt_g) || die "Unable to open $opt_g: $!\n" if ($opt_g);

sub debug_option {
    my($opt) = @_;
    return undef unless defined($opt_D);
    return ($opt_D =~ m/$opt/);
}

my $previous_was_deletion = 0;
my $debug_reconstruction = debug_option('R');
my $debug_splice = debug_option('S');
my $debug_commit_header = debug_option('H');
my $debug_diff_header = debug_option('D');
my $debug_diff_extended = debug_option('E');
my $debug_range_header = debug_option('@');
my $debug_commit_changes = debug_option('C');
my $debug_push_cc = debug_option('P');
my $debug_loc = debug_option('L');

if (debug_option('u')) {
    test_line_details();
    exit 0;
}

my $state = 'commit';
$_ = <>;
chop;

my ($old, $new);
my $op;
my ($commit, $hash, $timestamp);
my %flt;
my %binary;
my @cc;

my @delete_records;

my $added_lines;
my $removed_lines;
my $oref;
my $nref;

for (;;) {
    if ($state eq 'commit') {
        process_last_commit() if (defined($hash));
        ($commit, $hash, $timestamp) = split;
        print "commit $hash $timestamp\n" if ($opt_c || $debug_commit_header);
        print STDERR "commit $hash $timestamp\n" if (!$debug_reconstruction && !$opt_q);

        $_ = <>;
        if (!defined($_)) {
            $state = 'EOF';
        } elsif (/^$/) {
            $_ = <>;
            if (!defined($_)) {
                $state = 'EOF';
            } elsif (/^diff /) {
                $state = 'diff';
                chop;
            } elsif (/^commit /) {
                chop;
            } else {
                bail_out('Expecting diff, commit, or EOF');
            }
        } elsif (/^commit /) {
            chop;
        } else {
            bail_out('Expecting an empty line or commit');
        }
    } elsif ($state eq 'diff') {
        hide_escaped_quotes();
        bail_out('Expecting a diff command') unless (
            m/^diff --git a\/([^ ]*) b\/(.*)/ ||
            m/^diff --git "a\/((?:[^"\\]|\\.)*)" "b\/((?:[^"\\]|\\.)*)"/ ||
            m/^diff --git a\/([^ ]*) "b\/((?:[^"\\]|\\.)*)"/ ||
            m/^diff --git "a\/((?:[^"\\]|\\.)*)" b\/(.*)/ ||
            m/^diff --git a\/(.*) b\/(.*)/);
        $old = $1;
        $new = $2;
        $old = unescape($old) if (/\"/);
        $new = unescape($new) if (/\"/);

        print "$_\n" if ($debug_diff_header);
        print "old=[$old] new=[$new]\n" if ($debug_diff_header);

        $oref = defined($flt{$old}) ? [@{$flt{$old}}] : [];
        $nref = ($old eq $new) ? $oref : defined($flt{$new}) ? [@{$flt{$new}}] : [];

        $state = 'EOF';
        my $from;
        $op = 'inplace';
        while (<>) {
            print "diff extended header: $_" if ($debug_diff_extended);
            chop;
            if (/^--- /) {

                $_ = <>;

                $_ = <>;
                chop;
                $state = 'range';
                $added_lines = $removed_lines = 0;
                last;
            } elsif (/^(copy|rename) from (.*)/) {
                $from = unquote_unescape($2);
            } elsif (/^rename to (.*)/) {
                my $to = unquote_unescape($1);
                $op = 'rename';
                bail_out('Missing rename from') unless (defined($from));
                push(@cc, { op => 'del', path => $from });
                push(@cc, { op => 'set', path => $to, lines => [@{$flt{$from}}] });
                $oref = $nref = [@{$flt{$old}}];
                $binary{$to} = 1 if ($binary{$from});

                # Update line_modifications to reflect file rename
                foreach my $key (keys %line_modifications) {
                    if ($key =~ /^\Q$from\E:(.*)$/) {
                        my $line_id = $1;
                        my $new_key = "$to:$line_id";
                        $line_modifications{$new_key} = $line_modifications{$key};
                        delete $line_modifications{$key};
                    }
                }
            } elsif (/^copy to (.*)/) {
                my $to = unquote_unescape($1);
                $op = 'copy';
                bail_out('Missing copy from') unless (defined($from));
                push(@cc, { op => 'set', path => $to, lines => [@{$flt{$from}}] });
                $loc += $#{$flt{$from}} + 1 if ($opt_g && output_source_code($to));
                $nref = [@{$flt{$old}}];
                $binary{$to} = 1 if ($binary{$from});
            } elsif (/^commit /) {
                $state = 'commit';
                last;
            } elsif (/^diff --git /) {
                $state = 'diff';
                last;
            } elsif (/^new file mode /) {
                push(@cc, { op => 'set', path => $old, lines => [] });
            } elsif (/^deleted file mode /) {
                $op = 'del';
                push(@cc, { op => 'del', path => $old });
                if (!$debug_reconstruction && output_source_code($old)) {
                    for my $l (@{$flt{$old}}) {
                        if ($opt_c) {
                            print "$l\n";
                        } else {
                            push(@delete_records, "$l $timestamp");
                        }
                    }
                }
            } elsif (/^Binary files ([^ ]*) and ([^ ]*) differ/) {
                $binary{$old} = 1;
                $_ = <>;
                if (!defined($_)) {
                    $state = 'EOF';
                    last;
                } elsif (/^commit /) {
                    chop;
                    $state = 'commit';
                    last;
                } elsif (/^diff --git /) {
                    chop;
                    $state = 'diff';
                    last;
                } else {
                    bail_out('Expected diff, commit, or EOF');
                }
            }
        }
    } elsif ($state eq 'range') {
        print "$_\n" if ($debug_range_header);
        my ($at1, $old_range, $new_range, $at2) = split;
        bail_out('Expecting a diff range') unless ($at1 eq '@@' && $at2 eq '@@');
        my ($old_start, $old_end) = range_parse($old_range);
        my ($new_start, $new_end) = range_parse($new_range);
        $_ = <>;
        my ($old_line_num, $new_line_num);
        $old_line_num = $old_start;
        $new_line_num = $new_start;
        my $binary = exists($binary{$old});
        my $output_source_code = output_source_code($old);

        my @deleted_block = ();
        my @added_block = ();
        my $processing_block = 0;

        while (defined($_)) {
            if (/^-(.*)/) {
                my $content = $1;
                push @deleted_block, { file => $old, line_number => $old_line_num, content => $content };
                process_line_change($old, $old_line_num, $content, 'delete');
                $loc-- if ($output_source_code);
                $old_line_num++;
                $processing_block = 1;
            } elsif (/^\+(.*)/) {
                my $content = $1;
                push @added_block, { file => $new, line_number => $new_line_num, content => $content };
                $loc++ if ($output_source_code);
                $new_line_num++;
                $processing_block = 1;
            } elsif (/^ (.*)/ || /^\\ No newline at end of file/) {
                # Process the blocks if any
                if ($processing_block) {
                    process_blocks(\@deleted_block, \@added_block);
                    @deleted_block = ();
                    @added_block = ();
                    $processing_block = 0;
                }
                $old_line_num++ unless /^\\ No newline at end of file/;
                $new_line_num++ unless /^\\ No newline at end of file/;
            } else {
                # End of hunk
                last;
            }
            $_ = <>;
        }

        # Process any remaining blocks
        if ($processing_block) {
            process_blocks(\@deleted_block, \@added_block);
        }

        push_to_cc();
        if (!defined($_)) {
            $state = 'EOF';
        } elsif (/^@@ /) {
            chop;
            $state = 'range';
        } elsif (/^diff --git /) {
            chop;
            $state = 'diff';
        } elsif (/^commit /) {
            chop;
            $state = 'commit';
        } else {
            bail_out('Expected diff, @@, commit, or EOF');
        }
        output_line_modifications();
    } elsif ($state eq 'EOF') {
        last;
    } else {
        bail_out("Invalid state $state");
    }
}
close $fh;

process_last_commit();
if ($debug_reconstruction) {
    reconstruct();
} else {
    dump_alive();
}
exit 0;

sub process_blocks {
    my ($deleted_block_ref, $added_block_ref) = @_;
    my @deleted_block = @$deleted_block_ref;
    my @added_block = @$added_block_ref;

    if (@deleted_block && @added_block) {
        # Both blocks exist; treat as modifications
        my $min = scalar @deleted_block < scalar @added_block ? scalar @deleted_block : scalar @added_block;
        for (my $i = 0; $i < $min; $i++) {
            my $deleted_line = $deleted_block[$i];
            my $added_line = $added_block[$i];
            process_line_change($deleted_line->{file}, $deleted_line->{line_number}, $deleted_line->{content}, 'modify', $added_line->{content}, $added_line->{line_number});
        }
        # Handle any extra lines
        if (scalar @deleted_block > $min) {
            for (my $i = $min; $i < scalar @deleted_block; $i++) {
                my $deleted_line = $deleted_block[$i];
                # Remaining deletions
                process_line_change($deleted_line->{file}, $deleted_line->{line_number}, $deleted_line->{content}, 'delete');
            }
        }
        if (scalar @added_block > $min) {
            for (my $i = $min; $i < scalar @added_block; $i++) {
                my $added_line = $added_block[$i];
                # Remaining additions
                process_line_change($added_line->{file}, $added_line->{line_number}, $added_line->{content}, 'add', undef, $added_line->{line_number});
            }
        }
    } elsif (@deleted_block) {
        # Only deletions
        for my $deleted_line (@deleted_block) {
            process_line_change($deleted_line->{file}, $deleted_line->{line_number}, $deleted_line->{content}, 'delete');
        }
    } elsif (@added_block) {
        # Only additions
        for my $added_line (@added_block) {
            process_line_change($added_line->{file}, $added_line->{line_number}, $added_line->{content}, 'add', undef, $added_line->{line_number});
        }
    }
}

sub process_last_commit {
    my $delta = $loc - $prev_loc;

    print "prev_loc=$prev_loc loc=$loc delta=$delta\n" if ($debug_loc);
    my $eol = ($opt_d ? " $delta\n" : "\n");
    for (@delete_records) {
        print "$_", $eol;
    }
    undef @delete_records;

    commit_changes();
    print $growth_file "$timestamp $loc\n" if ($opt_g);
    $prev_loc = $loc;
}

sub process_line_change {
    my ($file, $line_number, $content, $action, $new_content, $new_line_number) = @_;
    my $line_id = md5_hex($content);
    my $key = "$file:$line_id";

    if ($action eq 'delete') {
        if (exists $line_modifications{$key}) {
            # Mark the line as deleted
            $line_modifications{$key}{deleted} = 1;
        }
    } elsif ($action eq 'add') {
        my $new_line_id = md5_hex($content);
        my $new_key = "$file:$new_line_id";
        if (exists $line_modifications{$new_key}) {
            # Line exists; increment modification count
            $line_modifications{$new_key}{count} += 1;
            $line_modifications{$new_key}{deleted} = 0;
            $line_modifications{$new_key}{line_numbers}{$hash} = $new_line_number;
            $line_modifications{$new_key}{last_line_number} = $new_line_number;
            $line_modifications{$new_key}{content} = $content;  # Update content in case it changed
        } else {
            # New line; initialize modification count to 1
            $line_modifications{$new_key} = {
                count => 1,
                content => $content,
                deleted => 0,
                line_numbers => { $hash => $new_line_number },
                last_line_number => $new_line_number,
            };
        }
    } elsif ($action eq 'modify') {
        my $new_line_id = md5_hex($new_content);
        my $new_key = "$file:$new_line_id";
        # Map old line to new line
        if (exists $line_modifications{$key}) {
            $line_modifications{$key}{count} += 1;
            $line_modifications{$key}{deleted} = 0;
            $line_modifications{$key}{line_numbers}{$hash} = $new_line_number;
            $line_modifications{$key}{last_line_number} = $new_line_number;
            $line_modifications{$key}{content} = $new_content;
            # Update the key in the hash
            $line_modifications{$new_key} = delete $line_modifications{$key};
        } else {
            # Line didn't exist; perhaps this is the first time
            $line_modifications{$new_key} = {
                count => 1,
                content => $new_content,
                deleted => 0,
                line_numbers => { $hash => $new_line_number },
                last_line_number => $new_line_number,
            };
        }
    }
}

sub reconstruct {
    my $base_dir = 'RECONSTRUCTION';
    remove_tree($base_dir);
    for my $f (keys %flt) {
        next if ($f eq '/dev/null');
        next unless defined($flt{$f});
        my $path = "$base_dir/$f";
        my $dir = $path;
        $dir =~ s|[^/]*$||;
        make_path($dir);
        open(my $out, '>', $path) || die "Unable to open $path: $!\n";
        for my $line (@{$flt{$f}}) {
            print $out substr($line, 1);
        }
    }
}

sub dump_alive {
    my $eol;

    if ($opt_c) {
        print "END\n";
        $eol = "\n";
    } else {
        $eol = " alive NA\n";
    }

    for my $f (keys %flt) {
        next if ($f eq '/dev/null');
        next unless defined($flt{$f});
        next unless (output_source_code($f));
        for my $line (@{$flt{$f}}) {
            print $line, $eol;
        }
    }
}

sub bail_out {
    my ($expect) = @_;
    print STDERR "commit $hash $timestamp\n";
    print STDERR "Line $.: Unexpected $_\n";
    print STDERR "($expect)\n";
    reconstruct();
    exit 1;
}

sub range_parse {
    my ($range) = @_;
    if ($range =~ m/[+-](\d+)\,(\d+)$/) {
        if ($2 == 0) {
            return (0, 0);
        } else {
            return ($1 - 1, $1 + $2 - 1);
        }
    } elsif ($range =~ m/[+-](\d+)$/) {
        return ($1 - 1, $1);
    } else {
        bail_out('Expecting a diff range');
    }
}

sub commit_changes {
    for my $rec (@cc) {
        print "Change ($rec->{op}) $rec->{path}\n" if ($debug_commit_changes);
        if ($rec->{op} eq 'set') {
            if (defined($opt_d)) {
                my $delta = $loc - $prev_loc;
                for (@{$rec->{lines}}) {
                    if ($opt_t || $opt_l) {
                        $_ =~ s/^$timestamp ([A-Z])/$timestamp $delta $1/;
                    } else {
                        $_ .= " $delta" if ($_ eq $timestamp);
                    }
                }
            }
            $flt{$rec->{path}} = $rec->{lines};
        } elsif ($rec->{op} eq 'del') {
            delete $flt{$rec->{path}};
            delete $binary{$rec->{path}};
        } else {
            bail_out("Unknown change record $rec->{op}");
        }
    }
    undef @cc;

    if (defined($opt_e) && $opt_e eq $hash) {
        reconstruct();
        exit 0;
    }
}

sub push_to_cc {
    print "op=$op $old $new\n" if ($debug_push_cc);
    return if ($op eq 'del');
    push(@cc, { op => 'set', path => $old, lines => $oref }) if ($oref != $nref && $op ne 'copy');
    push(@cc, { op => 'set', path => $new, lines => $nref });
}

sub output_source_code {
    return 1 unless ($opt_s);
    my ($name) = @_;
    return ($name =~ m/\.(C|c|cc|cpp|cs|cxx|hh|hpp|h\+\+|c\+\+|h|H|hxx|java|((php[3457s]?)|pht|php-s)|py)$/);
}

sub hide_escaped_quotes {
    s/([^\\])\\\"/$1\001/g;
}

sub unquote_unescape {
    my ($n) = @_;
    return $n unless (/\"/);

    $n =~ s/([^\\])\\\"/$1\001/g;
    $n =~ s/\"//g;
    return unescape($n);
}

sub unescape {
    my ($n) = @_;

    $n =~ s/\001/"/g;
    $n =~ s/\\t/\t/g;
    $n =~ s/\\n/\n/g;
    $n =~ s/\\"/\"/g;
    $n =~ s/\\(\d{3})/chr(oct($1))/ge;
    $n =~ s/\\\\/\\/g;
    return $n;
}

sub line_details {
    my ($l) = @_;

    my $len = length($l);

    my $string = 0;
    while ($l =~ s/\"[^"]*\"//) {
        $string++;
    }
    while ($l =~ s/\'[^']*\'//) {
        $string++;
    }

    my $comment = (($l =~ s/\/\*.*//) || ($l =~ s/\#.*//) || ($l =~ s/\/\/.*//)) + 0;

    while ($l =~ s/\t+/' ' x (length($&) * 8 - length($`) % 8)/e) {
    }
    $l =~ /^( *)/g;
    my $startspace = length($1);

    my $comma = () = $l =~ /\,/g;
    my $bracket = () = $l =~ /\(/g;
    my $access = () = $l =~ /\.[^0-9]|\-\>/g;
    my $assignment = () = $l =~ /[^<>!~=]\=[^=]|\<\<\=|\>\>\=/g;
    my $scope = () = $l =~ /\{|(:\s*$)/g;
    my $array = () = $l =~ /\[/g;
    my $logical = () = $l =~ /\=\=|[^>]\>\=|[^<]\<\=|\!\=|[^<]\<[^<]|[^->]\>[^>]|\!|\|\||\&\&|\bor\b|\band\b|\bnot\b|\bis\b/g;
    return "$len $startspace $string $comment $comma $bracket $access $assignment $scope $array $logical";
}

sub str_equal {
    my($a, $b) = @_;

    if ($a ne $b) {
        print STDERR "Expected\t[$a]\nObtained\t[$b]\n";
    }
}

sub output_line_modifications {
    for my $key (sort keys %line_modifications) {
        my ($file, $line_id) = split(/:/, $key);
        my $data = $line_modifications{$key};
        my $count = $data->{count};
        my $content = $data->{content};
        my $status = $data->{deleted} ? 'Deleted' : 'Active';
        my $line_number = $data->{last_line_number} // 'N/A';
        $csv->say($fh, [$file, $count, $status, $line_number, $content]);
        print "File: $file, Modifications: $count, Status: $status, Line Number: $line_number, Content: $content\n";
    }
}

sub test_line_details {
         # l s s c c b a a s a l
    str_equal("2 0 0 0 0 0 0 0 0 0 0", line_details("xx"));
	str_equal("3 0 1 0 0 0 0 0 0 0 0", line_details("'x'"));
	str_equal("3 0 0 1 0 0 0 0 0 0 0", line_details('#x('));
	str_equal("3 0 0 1 0 0 0 0 0 0 0", line_details('/*('));
	str_equal("3 0 0 1 0 0 0 0 0 0 0", line_details('//('));
	str_equal("5 0 0 0 2 0 0 0 0 0 0", line_details('a,b,c'));
	str_equal("2 0 0 0 0 2 0 0 0 0 0", line_details('(('));
	str_equal("3 0 0 0 0 0 1 0 0 0 0", line_details('a.b'));
	str_equal("4 0 0 0 0 0 1 0 0 0 0", line_details('a->b'));
	str_equal("3 0 0 0 0 0 0 0 0 0 0", line_details('1.2'));
	str_equal("3 0 0 0 0 0 0 1 0 0 0", line_details('a=b'));
	str_equal("5 0 0 0 0 0 0 1 0 0 0", line_details('a<<=b'));
	str_equal("4 0 0 0 0 0 0 1 0 0 0", line_details('a*=b'));
	str_equal("1 0 0 0 0 0 0 0 1 0 0", line_details('{'));
	str_equal("2 0 0 0 0 0 0 0 1 0 0", line_details(': '));
	str_equal("2 0 0 0 0 0 0 0 1 0 0", line_details('x:'));
	str_equal("1 0 0 0 0 0 0 0 0 1 0", line_details('['));
	str_equal("2 0 0 0 0 0 0 0 0 0 1", line_details('=='));
	str_equal("3 0 0 0 0 0 0 0 0 0 1", line_details('a>='));
	str_equal("3 0 0 0 0 0 0 0 0 0 1", line_details('b<='));
	str_equal("2 0 0 0 0 0 0 0 0 0 1", line_details('!='));
	str_equal("3 0 0 0 0 0 0 0 0 0 1", line_details('a<b'));
	str_equal("4 0 0 0 0 0 0 0 0 0 0", line_details('a<<b'));
	str_equal("3 0 0 0 0 0 0 0 0 0 1", line_details('a>b'));
	str_equal("2 0 0 0 0 0 0 0 0 0 2", line_details('!!'));
	str_equal("2 0 0 0 0 0 0 0 0 0 1", line_details('||'));
	str_equal("2 0 0 0 0 0 0 0 0 0 1", line_details('&&'));
	str_equal("7 0 0 0 0 0 0 0 0 0 1", line_details('a and b'));
	str_equal("6 0 0 0 0 0 0 0 0 0 1", line_details('a or b'));
	str_equal("5 0 0 0 0 0 0 0 0 0 1", line_details('not b'));
	str_equal("4 0 0 0 0 0 0 0 0 0 0", line_details('notb'));
	str_equal("6 0 0 0 0 0 0 0 0 0 2", line_details('is not'));
	str_equal("2 1 0 0 0 0 0 0 0 0 0", line_details(' x'));
	str_equal("4 3 0 0 0 0 0 0 0 0 0", line_details('   x'));
	str_equal("1 8 0 0 0 0 0 0 0 0 0", line_details("\t"));
	str_equal("3 16 0 0 0 0 0 0 0 0 0", line_details("\t\tx"));
}
