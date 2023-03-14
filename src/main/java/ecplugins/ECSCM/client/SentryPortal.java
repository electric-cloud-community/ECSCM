
// SentryPortal.java --
//
// SentryPortal.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.electriccloud.commander.client.ChainedCallback;
import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.Schedule;
import com.electriccloud.commander.client.requests.CommanderRequest;
import com.electriccloud.commander.client.requests.CreateScheduleRequest;
import com.electriccloud.commander.client.requests.SetPropertyRequest;
import com.electriccloud.commander.client.responses.DefaultPropertyCallback;
import com.electriccloud.commander.client.responses.DefaultScheduleCallback;
import com.electriccloud.commander.gwt.client.ui.FormBuilder;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;
import com.google.gwt.user.client.Window.Location;
import ecinternal.client.ui.ProcedurePicker;
import ecinternal.client.ui.ProjectPicker;

import java.util.ArrayList;
import java.util.List;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createLinkUrl;

/**
 * Basic component that is meant to be cloned and then customized to perform a
 * real function.
 */
public class SentryPortal
    extends CustomEditorPortalBase
{

    //~ Instance fields --------------------------------------------------------

    private String          m_projectName;
    private ProcedurePicker m_ppProcedure;

    //~ Constructors -----------------------------------------------------------

    public SentryPortal(String projectName)
    {
        super("sentry", "New Continuous Integration Schedule", "Schedule Name",
            "getSCMTag");
        m_projectName = projectName;

        // Construct and set the default redirectTo URL
        CommanderUrlBuilder urlBuilder = createLinkUrl("projectDetails");

        urlBuilder.setParameter("projectName", m_projectName);
        urlBuilder.setParameter("tabGroup", "schedulesHeader");
        setDefaultRedirectToUrl(urlBuilder.buildString());
    }

    //~ Methods ----------------------------------------------------------------

    @Override protected String constructFinalRedirectToUrl()
    {
        CommanderUrlBuilder urlBuilder = createLinkUrl("editSchedule",
                "projects", m_projectName, "schedules", getObjectNameValue());

        urlBuilder.setParameter("redirectTo", getDefaultRedirectToUrl());

        return urlBuilder.buildString();
    }

    @Override protected String constructFormTypeValue()
    {
        String scmPluginName = getConfigList().getConfigPlugin(
                getScmConfigValue());

        return "$[/plugins/" + scmPluginName + "/project/scm_form/sentry]";
    }

    @Override protected String constructObjectPropertyPath()
    {
        return "/projects/" + m_projectName + "/schedules/"
            + getObjectNameValue();
    }

    @Override protected FormBuilder initializeFormTable()
    {
        m_ppProcedure = getUIFactory().createProcedurePicker();

        FormBuilder         fb        = super.initializeFormTable();
        final ProjectPicker ppProject = getUIFactory().createProjectPicker();

        m_ppProcedure.setProjectBox(ppProject);
        fb.addRow(true, "Project Name:",
            getUIFactory().getInlineHelpMessages().projectName(),
            "subproject", null, ppProject);
        fb.addRow(true, "Procedure Name:",
            getUIFactory().getInlineHelpMessages().procedureName(),
            "subproject", null,
            m_ppProcedure);

        return fb;
    }

    @Override protected void submit()
    {
        setStatus("Saving...");
        clearAllErrors();

        FormBuilder formBuilder = (FormBuilder) getFormTable();

        if (!formBuilder.validate()) {
            clearStatus();

            return;
        }

        createObjectAndSetProperties();
    }

    private void createObjectAndSetProperties()
    {
        CreateScheduleRequest request = getRequestFactory()
                .createCreateScheduleRequest();

        request.setProjectName(m_projectName);
        request.setScheduleName(getObjectNameValue());
        request.setProcedureName(m_ppProcedure.getValue());
        request.setScheduleDisabled(true);
        request.setCallback(new DefaultScheduleCallback(this) {
                @Override public void handleResponse(Schedule response)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug(
                            "Commander request completed successfully");
                    }

                    setPropertiesAndRedirect();
                }
            });
        doRequest(request);
    }

    private void setPropertiesAndRedirect()
    {
        List<CommanderRequest<?>> requests              =
            new ArrayList<CommanderRequest<?>>();
        DefaultPropertyCallback   singleRequestCallback =
            new DefaultPropertyCallback(this) {
                @Override public void handleResponse(Property response)
                {
                    // No-op
                }
            };

        // Save formType & scmConfig properties
        String                   customEditorDataPath =
            constructObjectPropertyPath()
                + "/ec_customEditorData";
        String                   formTypePath         = customEditorDataPath
                + "/formType";
        String                   formTypeValue        =
            constructFormTypeValue();
        final SetPropertyRequest setPropertyRequest1  = getRequestFactory()
                .createSetPropertyRequest();

        setPropertyRequest1.setPropertyName(formTypePath);
        setPropertyRequest1.setValue(formTypeValue);
        setPropertyRequest1.setCallback(singleRequestCallback);

        // Add first PropertyRequest to Array
        requests.add(setPropertyRequest1);

        if (getLog().isDebugEnabled()) {
            getLog().debug("Property '" + formTypePath
                    + "' registered to be saved with value '" + formTypeValue
                    + "'");
        }

        String scmConfigPath  = customEditorDataPath
                + "/scmConfig";
        String scmConfigValue = getScmConfigValue();

        // Create second setPropertyRequest
        final SetPropertyRequest setPropertyRequest2 = getRequestFactory()
                .createSetPropertyRequest();

        setPropertyRequest2.setPropertyName(scmConfigPath);
        setPropertyRequest2.setValue(scmConfigValue);
        setPropertyRequest2.setCallback(singleRequestCallback);

        // Add second PropertyRequest to Array
        requests.add(setPropertyRequest2);

        if (getLog().isDebugEnabled()) {
            getLog().debug("Property '" + scmConfigPath
                    + "' registered to be saved with value '" + scmConfigValue
                    + "'");
        }

        // Send off request to CommanderServer
        getRequestManager().doRequest(new ChainedCallback() {
                @Override public void onComplete()
                {
                    String redirectToUrl = constructFinalRedirectToUrl();

                    if (getLog().isDebugEnabled()) {
                        getLog().debug("Redirecting to: " + redirectToUrl);
                    }

                    Location.assign(redirectToUrl);
                }
            }, requests);
    } // end setPropertiesAndRedirect()
}
