# Makefile.PL

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'YourProjectName',
    VERSION_FROM => 'src/lib/LineModificationTracker.pm', # Change this to your main module file with $VERSION
    PREREQ_PM    => {
        'Perl::Tidy'       => '0',  # Required for Perl code formatting
        'Perl::Critic'     => '0',  # Required for Perl linting
        'Test::More'       => '0',  # Required for testing
        'JSON'             => '0',  # Required for JSON processing
        'LWP::UserAgent'   => '0',  # Required for HTTP client
        # Add other dependencies as needed
    },
    ABSTRACT     => 'Description of your project.',
    AUTHOR       => 'Your Name <your.email@example.com>',
);
