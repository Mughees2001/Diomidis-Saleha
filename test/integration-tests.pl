#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 13;      
use lib '../src';               
use LineModificationTracker;
use Digest::MD5 qw(md5_hex);
use Text::CSV;
use Test::Deep qw(cmp_deeply);

# Integration Test 1: Process Line Addition
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_add_001';

    my $diff_file = 'fixtures/sample_diff_addition.diff';
    open my $fh, '<', $diff_file or die "Cannot open $diff_file: $!";
    local $/ = undef;
    my $diff_text = <$fh>;
    close $fh;

    $tracker->process_diff($diff_text);

    my $expected_line_id = md5_hex('This is a newly added line.');
    my $expected_modifications = {
        "file_add.txt:$expected_line_id" => {
            count            => 1,
            content          => 'This is a newly added line.',
            deleted          => 0,
            line_numbers     => { 'commit_add_001' => 1 },
            last_line_number => 1,
        },
    };

    cmp_deeply(
        $tracker->{line_modifications},
        $expected_modifications,
        'Integration Test 1: Process addition diff correctly'
    );
}

# Integration Test 2: Process Line Deletion
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_del_001';
    my $line_content = 'This line will be deleted.';
    my $line_id = md5_hex($line_content);
    $tracker->{line_modifications}{"file_delete.txt:$line_id"} = {
        count            => 1,
        content          => $line_content,
        deleted          => 0,
        line_numbers     => { 'commit_del_001' => 1 },
        last_line_number => 1,
    };

    my $diff_file = 'fixtures/sample_diff_deletion.diff';
    open my $fh, '<', $diff_file or die "Cannot open $diff_file: $!";
    local $/ = undef;
    my $diff_text = <$fh>;
    close $fh;

    $tracker->process_diff($diff_text);

    is(
        $tracker->{line_modifications}{"file_delete.txt:$line_id"}{deleted},
        1,
        'Integration Test 2: Process deletion diff correctly'
    );
}

# Integration Test 3: Process Line Modification
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_mod_001';
    my $old_line_content = 'Old content line.';
    my $old_line_id = md5_hex($old_line_content);
    $tracker->{line_modifications}{"file_modify.txt:$old_line_id"} = {
        count            => 1,
        content          => $old_line_content,
        deleted          => 0,
        line_numbers     => { 'commit_mod_001' => 1 },
        last_line_number => 1,
    };

    my $diff_file = 'fixtures/sample_diff_modification.diff';
    open my $fh, '<', $diff_file or die "Cannot open $diff_file: $!";
    local $/ = undef;
    my $diff_text = <$fh>;
    close $fh;

    $tracker->process_diff($diff_text);

    my $new_line_content = 'New content line.';
    my $new_line_id = md5_hex($new_line_content);
    my $expected_modifications = {
        "file_modify.txt:$new_line_id" => {
            count            => 1,
            content          => 'New content line.',
            deleted          => 0,
            line_numbers     => { 'commit_mod_001' => 1 },
            last_line_number => 1,
        },
    };

    cmp_deeply(
        $tracker->{line_modifications},
        $expected_modifications,
        'Integration Test 3: Process modification diff correctly'
    );
}

# # Integration Test 4: Process multiple hunks in a diff correctly
# {
#     my $tracker = LineModificationTracker->new();
#     $tracker->{hash} = 'commit_multi_001';

#     my $diff_file = 'fixtures/sample_diff_multiple_hunks.diff';
#     open my $fh, '<', $diff_file or die "Cannot open $diff_file: $!";
#     local $/ = undef;
#     my $diff_text = <$fh>;
#     close $fh;

#     # Pre-populate with old lines that will be modified
#     my $old_line_content1 = 'First old line.';
#     my $old_line_id1 = md5_hex($old_line_content1);
#     $tracker->{line_modifications}{"file_multi.txt:$old_line_id1"} = {
#         count            => 1,
#         content          => $old_line_content1,
#         deleted          => 0,
#         line_numbers     => { 'commit_multi_001' => 1 },
#         last_line_number => 1,
#     };

#     my $old_line_content2 = 'Second old line.';
#     my $old_line_id2 = md5_hex($old_line_content2);
#     $tracker->{line_modifications}{"file_multi.txt:$old_line_id2"} = {
#         count            => 1,
#         content          => $old_line_content2,
#         deleted          => 0,
#         line_numbers     => { 'commit_multi_001' => 3 },
#         last_line_number => 3,
#     };

#     $tracker->process_diff($diff_text);

#     my $new_line_content1 = 'First modified line.';
#     my $new_line_id1 = md5_hex($new_line_content1);
#     my $new_line_content2 = 'Second modified line.';
#     my $new_line_id2 = md5_hex($new_line_content2);

#     my $expected_modifications = {
#         "file_multi.txt:$new_line_id1" => {
#             count            => 1,
#             content          => 'First modified line.',
#             deleted          => 0,
#             line_numbers     => { 'commit_multi_001' => 2 },  # Assuming new_line_number=2
#             last_line_number => 2,
#         },
#         "file_multi.txt:$new_line_id2" => {
#             count            => 1,
#             content          => 'Second modified line.',
#             deleted          => 0,
#             line_numbers     => { 'commit_multi_001' => 4 },  # Assuming new_line_number=4
#             last_line_number => 4,
#         },
#     };

#     cmp_deeply(
#         $tracker->{line_modifications},
#         $expected_modifications,
#         'Integration Test 4: Process multiple hunks in a diff correctly'
#     );
# }


# Integration Test 5: Handle Binary Files
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_binary_001';

    my $diff_file = 'fixtures/sample_diff_binary.diff';
    open my $fh, '<', $diff_file or die "Cannot open $diff_file: $!";
    local $/ = undef;
    my $diff_text = <$fh>;
    close $fh;

    $tracker->process_diff($diff_text);
    my $expected_modifications = {};

    cmp_deeply(
        $tracker->{line_modifications},
        $expected_modifications,
        'Integration Test 5: Handle binary files correctly'
    );
}

# Integration Test 6: CSV Output Verification for Addition
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_csv_add_001';
    my $line_content = 'This is a newly added line.';
    my $line_id = md5_hex($line_content);
    $tracker->{line_modifications}{"file_add.txt:$line_id"} = {
        count            => 1,
        content          => $line_content,
        deleted          => 0,
        line_numbers     => { 'commit_csv_add_001' => 1 },
        last_line_number => 1,
    };

    my $output_file = 'fixtures/test_output_csv_addition.csv';
    $tracker->output_line_modifications($output_file);

    ok(-e $output_file, 'Integration Test 6: CSV output file generated');
    open my $csv_fh, '<:encoding(utf8)', $output_file or die "Cannot open $output_file: $!";
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });

    my $header = $csv->getline($csv_fh);
    cmp_deeply(
        $header,
        ['File', 'Modification Count', 'Status', 'Last Line Number', 'Last Content'],
        'Integration Test 6: CSV Header'
    );

    my $data = $csv->getline($csv_fh);
    cmp_deeply(
        $data,
        ['file_add.txt', 1, 'Active', 1, 'This is a newly added line.'],
        'Integration Test 6: CSV Data Line for Addition'
    );

    close $csv_fh;

    # Clean up
    unlink $output_file;
}

# Integration Test 7: CSV Output Verification for Deletion
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_csv_del_001';
    my $line_content = 'This line will be deleted.';
    my $line_id = md5_hex($line_content);
    $tracker->{line_modifications}{"file_delete.txt:$line_id"} = {
        count            => 1,
        content          => $line_content,
        deleted          => 1,
        line_numbers     => { 'commit_csv_del_001' => 1 },
        last_line_number => 1,
    };

    my $output_file = 'fixtures/test_output_csv_deletion.csv';
    $tracker->output_line_modifications($output_file);

    ok(-e $output_file, 'Integration Test 7: CSV output file generated for deletion');
    open my $csv_fh, '<:encoding(utf8)', $output_file or die "Cannot open $output_file: $!";
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });

    my $header = $csv->getline($csv_fh);
    cmp_deeply(
        $header,
        ['File', 'Modification Count', 'Status', 'Last Line Number', 'Last Content'],
        'Integration Test 7: CSV Header for Deletion'
    );

    my $data = $csv->getline($csv_fh);
    cmp_deeply(
        $data,
        ['file_delete.txt', 1, 'Deleted', 1, 'This line will be deleted.'],
        'Integration Test 7: CSV Data Line for Deletion'
    );

    close $csv_fh;
    unlink $output_file;
}

# Integration Test 8: CSV Output Verification for Modification
{
    my $tracker = LineModificationTracker->new();
    $tracker->{hash} = 'commit_csv_mod_001';
    my $line_content = 'New content line.';
    my $line_id = md5_hex($line_content);
    $tracker->{line_modifications}{"file_modify.txt:$line_id"} = {
        count            => 1,
        content          => $line_content,
        deleted          => 0,
        line_numbers     => { 'commit_csv_mod_001' => 1 },
        last_line_number => 1,
    };

    my $output_file = 'fixtures/test_output_csv_modification.csv';
    $tracker->output_line_modifications($output_file);

    ok(-e $output_file, 'Integration Test 8: CSV output file generated for modification');
    open my $csv_fh, '<:encoding(utf8)', $output_file or die "Cannot open $output_file: $!";
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });

    my $header = $csv->getline($csv_fh);
    cmp_deeply(
        $header,
        ['File', 'Modification Count', 'Status', 'Last Line Number', 'Last Content'],
        'Integration Test 8: CSV Header for Modification'
    );

    my $data = $csv->getline($csv_fh);
    cmp_deeply(
        $data,
        ['file_modify.txt', 1, 'Active', 1, 'New content line.'],
        'Integration Test 8: CSV Data Line for Modification'
    );

    close $csv_fh;
    unlink $output_file;
}

done_testing();
