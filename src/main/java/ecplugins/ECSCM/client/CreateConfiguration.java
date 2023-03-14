
// CreateConfiguration.java --
//
// CreateConfiguration.java is part of ElectricCommander.
//
// Copyright (c) 2005-2014 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;

import com.google.gwt.event.logical.shared.ValueChangeEvent;
import com.google.gwt.event.logical.shared.ValueChangeHandler;
import com.google.gwt.http.client.Request;
import com.google.gwt.http.client.RequestCallback;
import com.google.gwt.http.client.RequestException;
import com.google.gwt.http.client.Response;
import com.google.gwt.user.client.ui.Anchor;

import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.PropertySheet;
import com.electriccloud.commander.client.requests.GetPropertiesRequest;
import com.electriccloud.commander.client.requests.RunProcedureRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.DefaultRunProcedureResponseCallback;
import com.electriccloud.commander.client.responses.PropertySheetCallback;
import com.electriccloud.commander.client.responses.RunProcedureResponse;
import com.electriccloud.commander.gwt.client.requests.CgiRequestProxy;
import com.electriccloud.commander.gwt.client.ui.CredentialEditor;
import com.electriccloud.commander.gwt.client.ui.CredentialEditor.CredentialType;
import com.electriccloud.commander.gwt.client.ui.FormBuilder;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.ui.SimpleErrorBox;
import com.electriccloud.commander.gwt.client.ui.ValuedListBox;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;

import ecinternal.client.InternalFormBase;
import ecinternal.client.ui.CustomEditorLoader;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createPageUrl;
import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createUrl;

import static ecinternal.client.InternalComponentBaseFactory.getPluginName;

/**
 * Create SCM Configuration.
 */
public class CreateConfiguration
    extends InternalFormBase
{

    //~ Static fields/initializers ---------------------------------------------

    private static final String SCM_TYPE = "scmType";

    //~ Instance fields --------------------------------------------------------

    private Map<String, String> m_scmTypeMap;

    //~ Constructors -----------------------------------------------------------

    public CreateConfiguration()
    {
        super("scmCreate", "New Source Control Configuration");

        CommanderUrlBuilder urlBuilder = createPageUrl(getPluginName(),
                "configurations");

        setDefaultRedirectToUrl(urlBuilder.buildString());
        m_scmTypeMap = new HashMap<String, String>();
    }

    //~ Methods ----------------------------------------------------------------

    @Override protected FormTable initializeFormTable()
    {
        FormBuilder fb = getUIFactory().createFormBuilder();

        fb.setId(getIdPrefix() + "fb");

        // Create a drop-down list for selecting the SCM type
        ValuedListBox typeList = getUIFactory().createValuedListBox();

        typeList.setId(getIdPrefix() + "-types");
        typeList.addItem("");
        typeList.setValue("");
        typeList.addValueChangeHandler(new ValueChangeHandler<String>() {
                @Override public void onValueChange(
                        ValueChangeEvent<String> event)
                {
                    loadCreateConfigParams();
                }
            });
        fb.addRow(true, "SCM Type:",
            getUIFactory().getInlineHelpMessages()
                          .scmType(), SCM_TYPE, null, typeList);

        return fb;
    }

    @Override protected void load()
    {
        setStatus("Loading...");

        // Make a Commander getProperties requests to get the list of SCM types
        GetPropertiesRequest request = getRequestFactory()
                .createGetPropertiesRequest();

        request.setPath("/plugins/" + getPluginName() + "/project/scm_types");
        request.setCallback(new PropertySheetCallback() {
                @Override public void handleResponse(PropertySheet response)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug(
                            "Commander getProperties request returned: "
                                + response);
                    }

                    parseScmTypes(response);
                    clearStatus();
                }

                @Override public void handleError(CommanderError error)
                {

                    if ("NoSuchProperty".equals(error.getCode())) {
                        addErrorMessage("No SCM types found");
                    }
                    else {
                        addErrorMessage(error);
                    }
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("Issuing Commander request: " + request);
        }

        doRequest(request);
    }

    @Override protected void submit()
    {
        setStatus("Saving...");
        clearAllErrors();

        FormBuilder fb = (FormBuilder) getFormTable();

        if (!fb.validate()) {
            clearStatus();

            return;
        }

        // Build runProcedure request
        String              scmPlugin = m_scmTypeMap.get(getScmTypeValue());
        RunProcedureRequest request   = getRequestFactory()
                .createRunProcedureRequest();

        request.setProjectName("/plugins/" + scmPlugin + "/project");
        request.setProcedureName("CreateConfiguration");

        Map<String, String> params           = fb.getValues();
        Collection<String>  credentialParams = fb.getCredentialIds();

        for (String paramName : params.keySet()) {

            if (!SCM_TYPE.equals(paramName)) {

                if (credentialParams.contains(paramName)) {
                    CredentialEditor credential      = fb.getCredential(
                            paramName);
                    CredentialType   credentialType  =
                        credential.getCredentialType();
                    String           scredentialType = CredentialType.PASSWORD
                            .getName();

                    if (credentialType == CredentialType.CHOOSE) {
                        scredentialType = CredentialType.CHOOSE.getName();
                    }
                    else if (credentialType == CredentialType.KEY) {
                        scredentialType = CredentialType.KEY.getName();
                        request.addActualParameter("credentialType",
                                scredentialType);
                    }


                    request.addCredentialParameter(paramName,
                        credential.getUsername(), credential.getPassword());
                }
                else {
                    request.addActualParameter(paramName,
                        params.get(paramName));
                }
            }
        }

        request.setCallback(new DefaultRunProcedureResponseCallback(this) {
                @Override public void handleResponse(
                        RunProcedureResponse response)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug(
                            "Commander runProcedure request returned jobId: "
                                + response.getJobId());
                    }

                    waitForJob(response.getJobId()
                                       .toString());
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("Issuing Commander request: " + request);
        }

        doRequest(request);
    }

    private void loadCreateConfigParams()
    {

        // Clear out old params
        FormBuilder        fb       = (FormBuilder) getFormTable();
        Collection<String> paramIds = fb.getRowIds();

        for (String paramId : paramIds) {

            if (!SCM_TYPE.equals(paramId)) {
                fb.removeRow(paramId);
            }
        }

        // Load new params based on SCM type
        String scmPlugin = m_scmTypeMap.get(getScmTypeValue());

        if (!scmPlugin.isEmpty()) {
            CustomEditorLoader loader = new CustomEditorLoader(fb, this);

            loader.setCustomEditorPath("/plugins/" + scmPlugin
                    + "/project/scm_form/createConfig");
            loader.load();
        }
    }

    private void parseScmTypes(PropertySheet propertySheet)
    {
        Map<String, Property> propertyMap = propertySheet.getProperties();

        // Make sure we found at least 1 SCM type
        if (propertyMap.isEmpty()) {
            addErrorMessage("No SCM types found");

            return;
        }

        // Parse properties
        ValuedListBox typesList = (ValuedListBox) getFormTable().getWidget(
                SCM_TYPE, 1);

        for (Property property : propertyMap.values()) {
            String scmPlugin = property.getName();
            String scmType   = property.getValue();

            m_scmTypeMap.put(scmType, scmPlugin);
            typesList.addItem(scmType);
        }
    }

    private void waitForJob(final String jobId)
    {
        CgiRequestProxy     cgiRequestProxy = new CgiRequestProxy(
                getPluginName(), "monitorJob.cgi");
        Map<String, String> cgiParams       = new HashMap<String, String>();

        cgiParams.put("jobId", jobId);

        // Pass debug flag to CGI, which will use it to determine whether to
        // clean up a successful job
        if ("1".equals(getGetParameter("debug"))) {
            cgiParams.put("debug", "1");
        }

        try {
            cgiRequestProxy.issueGetRequest(cgiParams, new RequestCallback() {
                    @Override public void onError(
                            Request   request,
                            Throwable exception)
                    {
                        addErrorMessage("CGI request failed: ", exception);
                    }

                    @Override public void onResponseReceived(
                            Request  request,
                            Response response)
                    {
                        String responseString = response.getText();

                        if (getLog().isDebugEnabled()) {
                            getLog().debug(
                                "CGI response received: " + responseString);
                        }

                        if (responseString.startsWith("Success")) {

                            // We're done!
                            cancel();
                        }
                        else {
                            SimpleErrorBox      error      = getUIFactory()
                                    .createSimpleErrorBox(
                                        "Error occurred during configuration creation: "
                                        + responseString);
                            CommanderUrlBuilder urlBuilder = createUrl(
                                    "jobDetails.php").setParameter("jobId",
                                    jobId);

                            error.add(
                                new Anchor("(See job for details)",
                                    urlBuilder.buildString()));
                            addErrorMessage(error);
                        }
                    }
                });
        }
        catch (RequestException e) {
            addErrorMessage("CGI request failed: ", e);
        }
    }

    private String getScmTypeValue()
    {
        return ((FormBuilder) getFormTable()).getValue(SCM_TYPE);
    }
}
