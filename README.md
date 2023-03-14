# ECSCM plugin

The ECSCM plugin contains the base code common to all SCM plugins. In
addition, it provides the Continuous Integration (CI) checkout step
procedure in CloudBees CD/RO, which you can use to perform SCM checkout
using a CI configuration.

# Plugin procedures

## CICheckout

This procedure performs an SCM checkout using a Continuous Integration
(CI) configuration.

### Input

1.  Go to the CICheckout procedure.

2.  Enter the following parameters:

<table>
<colgroup>
<col style="width: 50%" />
<col style="width: 50%" />
</colgroup>
<thead>
<tr class="header">
<th style="text-align: left;">Parameter</th>
<th style="text-align: left;">Description</th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td style="text-align: left;"><p>Project</p></td>
<td style="text-align: left;"><p>The name of the project where the
operation runs. The default is $[/myJob/ec_ci_projectName].</p></td>
</tr>
<tr class="even">
<td style="text-align: left;"><p>CI Configuration</p></td>
<td style="text-align: left;"><p>The name of the CI configuration that
you created. The default is $[/myJob/ec_ci_configurationName].</p></td>
</tr>
<tr class="odd">
<td style="text-align: left;"><p>Preflight</p></td>
<td style="text-align: left;"><p>If this parameter is set to
<em>True</em>, this is a prefight checkout step. The default is
$[/myJob/ec_ci_preflight].</p></td>
</tr>
</tbody>
</table>

### Output

After the job runs, you can view the results on the Job Details page in
CloudBees CD/RO.

In the **CICheckout** step, click the Log button to see the diagnostic
information.

## ElectricSentry

This procedure processes the Continuous Integration (CI) tasks.

### Input

1.  Go to the ElectricSentry procedure.

2.  Click **Run**.

### Output

After the job runs, you can view the results on the Job Details page in
CloudBees CD/RO.

In the **ElectricSentry** step, click the Log button to see the
diagnostic information.

## RunMethod

This procedure runs a method in the specified SCM plugin.

### Input

1.  Go to the RunMethod procedure.

2.  Enter the following parameters and click **Run**:

<table>
<colgroup>
<col style="width: 50%" />
<col style="width: 50%" />
</colgroup>
<thead>
<tr class="header">
<th style="text-align: left;">Parameter</th>
<th style="text-align: left;">Description</th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td style="text-align: left;"><p>method</p></td>
<td style="text-align: left;"><p>The name of the method to run.
(Required)</p></td>
</tr>
<tr class="even">
<td style="text-align: left;"><p>plugin</p></td>
<td style="text-align: left;"><p>The name of the ECSCM plugin to use,
such as ECSCM-Perforce. (Required)</p></td>
</tr>
</tbody>
</table>

### Output

After the job runs, you can view the results on the Job Details page in
CloudBees CD/RO.

In the **RunMethod** step, click the Log button to see the diagnostic
information.

# Release notes

## ECSCM 2.3.5

-   Migrated to community

## ECSCM 2.3.3

-   The documentation has been migrated to the main documentation site.

-   Fixed a bug when disabled ECSCM-SentryMonitor schedule was enabling
    during plugin upgrade.

## ECSCM 2.3.2

-   Minor bugfixes and improvements.

## ECSCM 2.3.1

-   Renaming to "CloudBees"

-   Updated the plugin icon.

## ECSCM 2.3.0

-   Sentry (CI) schedules now can handle Pipelines and Releases.

-   Support for WebHooks has been added.

## ECSCM 2.2.12

-   Fixed censoring password with \*'s in git plugin

## ECSCM 2.2.11

-   Fixed handling of EF server errors in Sentry driver.

## ECSCM 2.2.10

-   Output job name in client preflight driver.

-   Fixed handling of EF server errors in Sentry driver.

## ECSCM 2.2.9

-   Fixed a bug with HTML data representation in changelog.

## ECSCM 2.2.8

-   Fixed bug with corruption of binary files in preflight.

## ECSCM 2.2.7

-   Make UTF-8 decoding non-strict in the plugin.

## ECSCM 2.2.6

-   Fix the issue where the *ecscm\_snapshot* property sheet was not
    created during the CICheckout procedure.

## ECSCM 2.2.5

-   Fix preflight for Eclipse integration.

## ECSCM 2.2.4

-   Add a new cleanup hook, which allows Commander perform actions on
    fatal errors.

## ECSCM 2.2.3

-   Add an option for choosing a private key in the configuration
    editor.

-   Added new hooks in the afterRunMethod and beforeRunMethod
    procedures.

## ECSCM-2.2.1

-   Fix incorrect warnings generated by postp in the CICheckout
    prccedure.

## ECSCM 2.2.0

-   Add a way for ECSCM plugins to pass string replacements for all
    standard output (STDOUT) and standard error (STDERR) connections
    from external commands. These are usually used to mask passwords.

## ECSCM 2.1.0

-   Add a post-process step called *Check for New Sources* to get errors
    when external commands are running and to get warnings when triggers
    are skipped.

## ECSCM 2.0.6

-   Fix a bug in CICheckout procedure where the actual parameters that
    you enter were not shown on the editStep page.

## ECSCM 2.0.5

-   Fix a bug about determining the schedules to check when there were
    multiple Sentry schedules.
