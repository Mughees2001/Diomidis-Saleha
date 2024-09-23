# LineModificationTracker.pm
package LineModificationTracker;

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Text::CSV;
use File::Path qw(make_path remove_tree);

sub new {
    my ($class) = @_;
    my $self = {
        line_modifications => {},
        csv                => Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" }),
        flt                => {},
        binary             => {},
        cc                 => [],
        loc                => 0,
        prev_loc           => 0,
        delete_records     => [],
        oref               => [],
        nref               => [],
        timestamp          => undef,
        hash               => undef,
    };
    bless $self, $class;
    return $self;
}

sub process_diff {
    my ($self, $diff_text) = @_;
    my @lines = split /\n/, $diff_text;
    my $state = 'start';
    my ($old_file, $new_file, $op);

    while (@lines) {
        my $line = shift @lines;
        if ($state eq 'start') {
            if ($line =~ /^diff --git a\/(.+?) b\/(.+)$/) {
                ($old_file, $new_file) = ($1, $2);
                $state = 'headers';
                $op = 'modify';
            }
        } elsif ($state eq 'headers') {
            if ($line =~ /^new file mode/) {
                $op = 'add';
            } elsif ($line =~ /^deleted file mode/) {
                $op = 'delete';
            } elsif ($line =~ /^index/) {
                # Ignore index line
            } elsif ($line =~ /^--- (.+)$/) {
                # Old file header
            } elsif ($line =~ /^\+\+\+ (.+)$/) {
                # New file header
            } elsif ($line =~ /^@@ (.+) @@/) {
                # Start of hunk
                unshift @lines, $line;
                $state = 'hunk';
            }
        } elsif ($state eq 'hunk') {
            if ($line =~ /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/) {
                my ($old_start, $old_count, $new_start, $new_count) = ($1, $2, $3, $4);
                $old_count ||= 1;
                $new_count ||= 1;
                my @old_lines = ();
                my @new_lines = ();
                while (@lines) {
                    $line = shift @lines;
                    if ($line =~ /^-/) {
                        push @old_lines, substr($line, 1);
                    } elsif ($line =~ /^\+/) {
                        push @new_lines, substr($line, 1);
                    } elsif ($line =~ /^ /) {
                        push @old_lines, substr($line, 1);
                        push @new_lines, substr($line, 1);
                    } elsif ($line =~ /^@@ /) {
                        unshift @lines, $line;
                        last;
                    } else {
                        # End of hunk
                        last;
                    }
                }
                # Process the old and new lines
                $self->_process_lines(
                    $old_file, $new_file,
                    $old_start, $new_start,
                    \@old_lines, \@new_lines,
                    $op
                );
            }
        }
    }
    # Commit changes
    $self->_commit_changes();
}

sub _process_lines {
    my ($self, $old_file, $new_file, $old_start, $new_start, $old_lines_ref, $new_lines_ref, $op) = @_;
    my @old_lines = @$old_lines_ref;
    my @new_lines = @$new_lines_ref;

    # Handling addition, deletion, and modification
    if ($op eq 'add') {
        for my $i (0 .. $#new_lines) {
            my $line_content = $new_lines[$i];
            my $line_number  = $new_start + $i;
            $self->_process_line_change(
                undef, $new_file,
                undef, $line_number,
                undef, $line_content,
                'add'
            );
        }
    } elsif ($op eq 'delete') {
        for my $i (0 .. $#old_lines) {
            my $line_content = $old_lines[$i];
            my $line_number  = $old_start + $i;
            $self->_process_line_change(
                $old_file, undef,
                $line_number, undef,
                $line_content, undef,
                'delete'
            );
        }
    } else {
        # Modification or unchanged lines
        my $max = scalar(@old_lines) > scalar(@new_lines) ? scalar(@old_lines) : scalar(@new_lines);
        for my $i (0 .. $max - 1) {
            my $old_line_content = $old_lines[$i] // undef;
            my $new_line_content = $new_lines[$i] // undef;
            my $old_line_number  = defined $old_line_content ? $old_start + $i : undef;
            my $new_line_number  = defined $new_line_content ? $new_start + $i : undef;

            if (defined $old_line_content && defined $new_line_content) {
                if ($old_line_content ne $new_line_content) {
                    # Line modified
                    $self->_process_line_change(
                        $old_file, $new_file,
                        $old_line_number, $new_line_number,
                        $old_line_content, $new_line_content,
                        'modify'
                    );
                } else {
                    # Line unchanged
                    # Optionally, track unchanged lines
                }
            } elsif (defined $old_line_content) {
                # Line deleted
                $self->_process_line_change(
                    $old_file, undef,
                    $old_line_number, undef,
                    $old_line_content, undef,
                    'delete'
                );
            } elsif (defined $new_line_content) {
                # Line added
                $self->_process_line_change(
                    undef, $new_file,
                    undef, $new_line_number,
                    undef, $new_line_content,
                    'add'
                );
            }
        }
    }
}

sub _process_line_change {
    my ($self, $old_file, $new_file, $old_line_number, $new_line_number, $old_content, $new_content, $action) = @_;
    if ($action eq 'delete') {
        my $old_line_id = md5_hex($old_content);
        my $old_key     = "$old_file:$old_line_id";
        if (exists $self->{line_modifications}{$old_key}) {
            $self->{line_modifications}{$old_key}{deleted} = 1;
        }
    } elsif ($action eq 'add') {
        my $new_line_id = md5_hex($new_content);
        my $new_key     = "$new_file:$new_line_id";
        $self->{line_modifications}{$new_key} = {
            count            => 1,
            content          => $new_content,
            deleted          => 0,
            line_numbers     => { $self->{hash} => $new_line_number },
            last_line_number => $new_line_number,
        };
    } elsif ($action eq 'modify') {
        my $old_line_id = md5_hex($old_content);
        my $new_line_id = md5_hex($new_content);
        my $old_key     = "$old_file:$old_line_id";
        my $new_key     = "$new_file:$new_line_id";

        if (exists $self->{line_modifications}{$old_key}) {
            # Increment the count for the old line
            $self->{line_modifications}{$old_key}{count} += 1;
            $self->{line_modifications}{$old_key}{content} = $new_content;
            $self->{line_modifications}{$old_key}{deleted} = 0;
            $self->{line_modifications}{$old_key}{line_numbers}{$self->{hash}} = $new_line_number;
            $self->{line_modifications}{$old_key}{last_line_number} = $new_line_number;

            # Transfer to the new line key with count set to 1
            $self->{line_modifications}{$new_key} = {
                count            => 1,  # Reset count for the new line
                content          => $new_content,
                deleted          => 0,
                line_numbers     => { $self->{hash} => $new_line_number },
                last_line_number => $new_line_number,
            };
            delete $self->{line_modifications}{$old_key};
        } else {
            # Line did not exist before, treat as new line
            $self->{line_modifications}{$new_key} = {
                count            => 1,
                content          => $new_content,
                deleted          => 0,
                line_numbers     => { $self->{hash} => $new_line_number },
                last_line_number => $new_line_number,
            };
        }
    }
}

sub _commit_changes {
    my ($self) = @_;
    # Process any pending changes (e.g., handle loc calculations)
    # For now, we just reset the delete_records array
    $self->{delete_records} = [];
}

sub output_line_modifications {
    my ($self, $output_file) = @_;
    open my $fh, ">:encoding(utf8)", $output_file or die "$output_file: $!";
    $self->{csv}->say($fh, ["File", "Modification Count", "Status", "Last Line Number", "Last Content"]);
    for my $key (sort keys %{ $self->{line_modifications} }) {
        my ($file, $line_id) = split(/:/, $key);
        my $data         = $self->{line_modifications}{$key};
        my $count        = $data->{count};
        my $content      = $data->{content};
        my $status       = $data->{deleted} ? 'Deleted' : 'Active';
        my $line_number  = $data->{last_line_number} // 'N/A';
        $self->{csv}->say($fh, [$file, $count, $status, $line_number, $content]);
    }
    close $fh;
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

    my $comma        = () = $l =~ /\,/g;
    my $bracket      = () = $l =~ /\(/g;
    my $access       = () = $l =~ /\.[^0-9]|\-\>/g;
    my $assignment   = () = $l =~ /[^<>!~=]\=[^=]|\<\<\=|\>\>\=/g;
    my $scope        = () = $l =~ /\{|(:\s*$)/g;
    my $array        = () = $l =~ /\[/g;
    my $logical      = () = $l =~ /\=\=|[^>]\>\=|[^<]\<\=|\!\=|[^<]\<[^<]|[^->]\>[^>]|\!|\|\||\&\&|\bor\b|\band\b|\bnot\b|\bis\b/g;

    return "$len $startspace $string $comment $comma $bracket $access $assignment $scope $array $logical";
}

1;  # End of LineModificationTracker.pm
