#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 12;  
use lib '../src/lib';              
use LineModificationTracker;
use Digest::MD5 qw(md5_hex); 

# Test 1: Line Details Function
{
    my $details = LineModificationTracker::line_details('a = b + c;');
    is($details, '10 0 0 0 0 0 0 1 0 0 0', 'line_details function works correctly');
}

# Test 2: Process Diff with Addition
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_hash';  # Set a dummy commit hash

    my $diff = <<'END_DIFF';
diff --git a/file.txt b/file.txt
--- a/file.txt
+++ b/file.txt
@@ -0,0 +1 @@
+This is a new line
END_DIFF

    $tracker->process_diff($diff);

    my $expected_line_id = md5_hex('This is a new line');
    my $expected_modifications = {
        "file.txt:$expected_line_id" => {
            count            => 1,
            content          => 'This is a new line',
            deleted          => 0,
            line_numbers     => { 'commit_hash' => 1 },
            last_line_number => 1,
        },
    };

    is_deeply(
        $tracker->{line_modifications},
        $expected_modifications,
        'Process diff with line addition'
    );
}

# Test 3: Process Diff with Deletion
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_hash';

    my $diff = <<'END_DIFF';
diff --git a/file.txt b/file.txt
--- a/file.txt
+++ b/file.txt
@@ -1 +0,0 @@
-This is a line to delete
END_DIFF

    my $line_id = md5_hex('This is a line to delete');
    $tracker->{line_modifications}{"file.txt:$line_id"} = {
        count            => 1,
        content          => 'This is a line to delete',
        deleted          => 0,
        line_numbers     => { 'commit_hash' => 1 },
        last_line_number => 1,
    };

    $tracker->process_diff($diff);

    is(
        $tracker->{line_modifications}{"file.txt:$line_id"}{deleted},
        1,
        'Process diff with line deletion'
    );
}

# Test 4: Process Diff with Modification - Count
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_hash';

    my $old_line_id = md5_hex('Old content');
    $tracker->{line_modifications}{"file.txt:$old_line_id"} = {
        count            => 1,
        content          => 'Old content',
        deleted          => 0,
        line_numbers     => { 'commit_hash' => 1 },
        last_line_number => 1,
    };

    my $diff = <<'END_DIFF';
diff --git a/file.txt b/file.txt
--- a/file.txt
+++ b/file.txt
@@ -1 +1 @@
-Old content
+New content
END_DIFF

    $tracker->process_diff($diff);

    my $new_line_id = md5_hex('New content');

    is(
        $tracker->{line_modifications}{"file.txt:$new_line_id"}{count},
        1,
        'Process diff with line modification - Count'
    );
}

# Test 5: Process Diff with Modification - Status
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_hash';

    my $old_line_id = md5_hex('Old content');
    $tracker->{line_modifications}{"file.txt:$old_line_id"} = {
        count            => 1,
        content          => 'Old content',
        deleted          => 0,
        line_numbers     => { 'commit_hash' => 1 },
        last_line_number => 1,
    };

    my $diff = <<'END_DIFF';
diff --git a/file.txt b/file.txt
--- a/file.txt
+++ b/file.txt
@@ -1 +1 @@
-Old content
+New content
END_DIFF

    $tracker->process_diff($diff);

    my $new_line_id = md5_hex('New content');

    is(
        $tracker->{line_modifications}{"file.txt:$new_line_id"}{deleted},
        0,
        'Process diff with line modification - Status'
    );
}

# Test 6: Output Line Modifications to CSV
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_hash';
    my $line_id = md5_hex('Line content');
    $tracker->{line_modifications}{"file.txt:$line_id"} = {
        count            => 2,
        content          => 'Line content',
        deleted          => 0,
        last_line_number => 3,
        line_numbers     => { 'commit_hash' => 3 },
    };

    my $output_file = 'test_output.csv';
    $tracker->output_line_modifications($output_file);

    ok(-e $output_file, 'CSV output file generated');

    open my $fh, '<:encoding(utf8)', $output_file or die "Cannot open $output_file: $!";
    my $header = <$fh>;
    chomp $header;
    is($header, 'File,"Modification Count",Status,"Last Line Number","Last Content"', 'CSV header is correct');

    my $data_line = <$fh>;
    chomp $data_line;
    my $expected_line = 'file.txt,2,Active,3,Line content';
    $expected_line = 'file.txt,2,Active,3,Line content';

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
    if ($csv->parse($data_line)) {
        my @fields = $csv->fields();
        is($fields[0], 'file.txt', 'CSV data line - File');
        is($fields[1], '2', 'CSV data line - Modification Count');
        is($fields[2], 'Active', 'CSV data line - Status');
        is($fields[3], '3', 'CSV data line - Last Line Number');
        is($fields[4], 'Line content', 'CSV data line - Last Content');
    } else {
        fail('Failed to parse CSV data line');
    }

    close $fh;

    unlink $output_file;
}

done_testing();
