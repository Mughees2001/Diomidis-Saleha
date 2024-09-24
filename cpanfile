perl '5.10.0';

requires 'Perl::Tidy';
requires 'Perl::Critic';
requires 'Test::More';

requires 'JSON';       

on 'test' => sub {
    requires 'Test::Simple';
    requires 'Test::Deep';
};

on 'develop' => sub {
    requires 'Test::Strict';
};
