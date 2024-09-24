# cpanfile

# Specify the Perl version
perl '5.10.0';

# Runtime dependencies
requires 'Perl::Tidy';
requires 'Perl::Critic';
requires 'Test::More';
requires 'JSON';             # Example: JSON processing module
requires 'LWP::UserAgent';   # Example: HTTP client module

# Test dependencies (if needed)
on 'test' => sub {
    requires 'Test::Simple';
    requires 'Test::Deep';
};

# Develop dependencies (if needed)
on 'develop' => sub {
    requires 'Test::Strict';
};

