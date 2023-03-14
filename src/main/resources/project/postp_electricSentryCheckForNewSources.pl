@::gMatchers = (
    {   id      => "ElectricSentry-checkNewSourcesCatchWarnings",
        pattern => q{Warning: An ElectricSentry schedule was skipped},
        action =>
            q{incValue("warnings");diagnostic("warning message found", "warning", 0,1);},
    },
    {   id      => "ElectricSentry-checkNewSourcesCatchErrors",
        pattern => q{Error: Return\s+\(.*\) from RunCommand.},
        action =>
            q{incValue("errors");diagnostic("non zero exit from external command", "error", 0,1);},
    }
);