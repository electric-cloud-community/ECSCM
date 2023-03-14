
// PreflightPortal.java --
//
// PreflightPortal.java is part of ElectricCommander.
//
// Copyright (c) 2005-2010 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.Collection;
import java.util.Map;

import com.google.gwt.event.logical.shared.ValueChangeEvent;
import com.google.gwt.event.logical.shared.ValueChangeHandler;
import com.google.gwt.user.client.Window.Location;
import com.google.gwt.user.client.ui.TextBox;

import ecinternal.client.InternalFormBase;

import com.electriccloud.commander.client.ChainedCallback;
import com.electriccloud.commander.client.domain.ProcedureStep;
import com.electriccloud.commander.client.requests.CreateStepRequest;
import com.electriccloud.commander.client.responses.DefaultProcedureStepCallback;
import com.electriccloud.commander.gwt.client.ui.FormBuilder;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.ui.ValuedListBox;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;
import com.electriccloud.commander.client.util.StringUtil;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createLinkUrl;

/**
 * Basic component that is meant to be cloned and then customized to perform a
 * real function.
 */
public class PreflightPortal
    extends InternalFormBase
{

    //~ Static fields/initializers ---------------------------------------------

    private static final String STEP_NAME_LABEL  = "Step Name:";
    private static final String STEP_NAME_KEY    = "stepName";
    private static final String SCM_CONFIG_LABEL = "SCM Configuration:";
    private static final String SCM_CONFIG_KEY   = "scmConfig";

    //~ Instance fields --------------------------------------------------------

    private String        m_projectName;
    private String        m_procedureName;
    private ScmConfigList m_configList;

    //~ Constructors -----------------------------------------------------------

    public PreflightPortal(
            String projectName,
            String procedureName)
    {
        super("preflightCreate", "New Extract Preflight Sources Step");
        m_projectName   = projectName;
        m_procedureName = procedureName;
        m_configList    = new ScmConfigList();

        // Construct and set the default redirectTo URL
        CommanderUrlBuilder urlBuilder = createLinkUrl("procedureDetails",
                "projects", m_projectName, "procedures", m_procedureName);

        setDefaultRedirectToUrl(urlBuilder.buildString());
    }

    //~ Methods ----------------------------------------------------------------

    @Override protected FormTable initializeFormTable()
    {
        FormBuilder fb = getUIFactory().createFormBuilder();

        fb.addRow(true, STEP_NAME_LABEL,
            getUIFactory().getInlineHelpMessages().stepName(),
            STEP_NAME_KEY, null,
            new TextBox());

        ValuedListBox scmConfig = getUIFactory().createValuedListBox();

        scmConfig.addItem("");
        scmConfig.setValue("");
        scmConfig.addValueChangeHandler(new ValueChangeHandler<String>() {
                @Override public void onValueChange(
                        ValueChangeEvent<String> event)
                {
                    renderPreflightParams();
                }
            });
        fb.addRow(true, SCM_CONFIG_LABEL,
            getUIFactory().getInlineHelpMessages().scmConfiguration(),
            SCM_CONFIG_KEY, null,
            scmConfig);

        return fb;
    }

    @Override protected void load()
    {
        setStatus("Loading...");

        ScmConfigListLoader loader = new ScmConfigListLoader(m_configList,
                "apf_driver", this, new ChainedCallback() {
                    @Override public void onComplete()
                    {
                        m_configList.populateConfigListBox(getScmConfig());

                        // Clear the status now that loading is complete
                        clearStatus();
                    }
                });

        loader.setEditorName("preflight");
        loader.load();
    }

    @Override protected void submit()
    {
        setStatus("Saving...");
        clearAllErrors();

        if (!((FormBuilder) getFormTable()).validate()) {
            clearStatus();

            return;
        }

        // Create the preflight step
        CreateStepRequest request = constructCreateStepRequest();

        request.setCallback(new DefaultProcedureStepCallback(this) {
                @Override public void handleResponse(ProcedureStep response)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug(
                            "Commander createStep request completed successfully");
                    }

                    // Redirect to the editStep page for the step we just
                    // created
                    String              stepName   =
                        ((FormBuilder) getFormTable()).getValue(STEP_NAME_KEY);
                    CommanderUrlBuilder urlBuilder = createLinkUrl("editStep",
                            "projects", m_projectName, "procedures",
                            m_procedureName, "steps", stepName);

                    urlBuilder.setParameter("redirectTo",
                        getDefaultRedirectToUrl());
                    Location.assign(urlBuilder.buildString());
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("Issuing Commander request: " + request);
        }

        doRequest(request);
    }

    private CreateStepRequest constructCreateStepRequest()
    {
        FormBuilder         fb          = (FormBuilder) getFormTable();
        Map<String, String> paramValues = fb.getValues();
        String              stepName    = paramValues.remove(STEP_NAME_KEY);
        CreateStepRequest   request     = getRequestFactory()
                .createCreateStepRequest();

        request.setProjectName(m_projectName);
        request.setProcedureName(m_procedureName);
        request.setStepName(stepName);

        // Call the "Preflight" procedure in the relevant plugin's project
        String configName   = paramValues.remove(SCM_CONFIG_KEY);
        String configPlugin = m_configList.getConfigPlugin(configName);

        request.setSubproject("/plugins/" + configPlugin + "/project");
        request.setSubprocedure("Preflight");

        // Add subprocedure actual parameters
        request.addActualParameter("config", configName);

        for (String paramName : paramValues.keySet()) {
            request.addActualParameter(paramName, paramValues.get(paramName));
        }

        return request;
    }

    private void renderPreflightParams()
    {

        // Clear out old params
        FormBuilder        fb       = (FormBuilder) getFormTable();
        Collection<String> paramIds = fb.getRowIds();

        for (String paramId : paramIds) {

            if (!STEP_NAME_KEY.equals(paramId)
                    && !SCM_CONFIG_KEY.equals(paramId)) {
                fb.removeRow(paramId);
            }
        }

        // Load new params
        String scmConfigValue = getScmConfig().getValue();

        if (!StringUtil.isEmpty(scmConfigValue)) {
            fb.addRowsWithXml(m_configList.getEditorDefinition(scmConfigValue));
        }
    }

    private ValuedListBox getScmConfig()
    {
        return (ValuedListBox) getFormTable().getWidget(SCM_CONFIG_KEY, 1);
    }
}
