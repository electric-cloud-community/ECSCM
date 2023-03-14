
// ScmConfigListLoader.java --
//
// ScmConfigListLoader.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.google.gwt.http.client.Request;
import com.google.gwt.http.client.RequestCallback;
import com.google.gwt.http.client.RequestException;
import com.google.gwt.http.client.Response;

import ecinternal.client.HasErrorPanel;
import ecinternal.client.Loader;

import com.electriccloud.commander.client.ChainedCallback;
import com.electriccloud.commander.gwt.client.Component;
import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.gwt.client.requests.CgiRequestProxy;
import com.electriccloud.commander.client.requests.CommanderRequest;
import com.electriccloud.commander.client.requests.GetPropertyRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.PropertyCallback;
import com.electriccloud.commander.client.util.StringUtil;

/**
 * Class responsible for populating a {@link ScmConfigList}.
 */
public class ScmConfigListLoader
    extends Loader
{

    //~ Instance fields --------------------------------------------------------

    private ScmConfigList   m_configList;
    private CgiRequestProxy m_cgiRequestProxy;
    private String          m_implementedMethod;

    /**
     * Editor means custom form xml that has been defined on a plugin. This
     * variable is used to figure out which property to read on a plugin
     */
    private String m_editorName;

    //~ Constructors -----------------------------------------------------------

    /**
     * @param  configList  a {@link ScmConfigList} to populate
     * @param  component
     * @param  callback    a {@link ChainedCallback} callback The {@link
     *                     ChainedCallback#onComplete()} gets called.
     */
    public ScmConfigListLoader(
            ScmConfigList   configList,
            Component       component,
            ChainedCallback callback)
    {
        this(configList, null, component, callback);
    }

    public ScmConfigListLoader(
            ScmConfigList   configList,
            String          implementedMethod,
            Component       component,
            ChainedCallback callback)
    {
        super(component, callback);
        m_configList        = configList;
        m_implementedMethod = implementedMethod;
        m_cgiRequestProxy   = new CgiRequestProxy("ECSCM", "ecscm.cgi");
    }

    //~ Methods ----------------------------------------------------------------

    /**
     * Caller must invoke this function to start loading process.
     */
    @Override public void load()
    {
        Map<String, String> cgiParams = new HashMap<String, String>();

        if (StringUtil.isEmpty(m_implementedMethod)) {
            cgiParams.put("cmd", "getCfgList");
        }
        else {
            cgiParams.put("cmd", "getImplementingCfgs");
            cgiParams.put("method", m_implementedMethod);
        }

        loadConfigs(cgiParams);
    }

    static String constructEditorRequestId(String pluginName)
    {
        return "getEditorForPlugin_" + pluginName;
    }

    GetPropertyRequest constructEditorRequest(
            String editorName,
            String pluginName)
    {
        GetPropertyRequest request =
            m_requestFactory.createGetPropertyRequest();

        request.setPropertyName("/plugins/" + pluginName + "/project/scm_form/"
                + editorName);
        request.setExpand(false);
        request.setRequestId(constructEditorRequestId(pluginName));

        return request;
    }

    /**
     * Delegates loading process to a CGI script.
     *
     * @param  cgiParams
     */
    private void loadConfigs(Map<String, String> cgiParams)
    {

        try {
            String request = m_cgiRequestProxy.issueGetRequest(cgiParams,
                    new RequestCallback() {
                        @Override public void onError(
                                Request   request,
                                Throwable exception)
                        {

                            if (m_component instanceof HasErrorPanel) {
                                ((HasErrorPanel) m_component).addErrorMessage(
                                    "Error loading SCM configuration list: ",
                                    exception);
                            }
                            else {
                                m_component.getLog()
                                           .error(exception);
                            }
                        }

                        @Override public void onResponseReceived(
                                Request  request,
                                Response response)
                        {
                            String responseString = response.getText();

                            if (m_component.getLog()
                                           .isDebugEnabled()) {
                                m_component.getLog()
                                           .debug(
                                               "Recieved CGI response: "
                                               + responseString);
                            }

                            String error = m_configList.parseResponse(
                                    responseString);

                            if (error != null) {

                                if (m_component instanceof HasErrorPanel) {
                                    ((HasErrorPanel) m_component)
                                        .addErrorMessage(error);
                                }
                                else {
                                    m_component.getLog()
                                               .error(error);
                                }
                            }
                            else {

                                if (StringUtil.isEmpty(m_editorName)
                                        || m_configList.isEmpty()) {

                                    // We're done!
                                    if (m_callback != null) {
                                        m_callback.onComplete();
                                    }
                                }
                                else {
                                    loadEditors();
                                }
                            }
                        }
                    });

            if (m_component.getLog()
                           .isDebugEnabled()) {
                m_component.getLog()
                           .debug("Issued CGI request: " + request);
            }
        }
        catch (RequestException e) {

            if (m_component instanceof HasErrorPanel) {
                ((HasErrorPanel) m_component).addErrorMessage(
                    "Error loading SCM configuration list: ", e);
            }
            else {
                m_component.getLog()
                           .error(e);
            }
        }
    }

    private void loadEditors()
    {

        // Load editor for each SCM plugin
        Set<String>               configPlugins = new HashSet<String>();
        List<CommanderRequest<?>> requests      =
            new ArrayList<CommanderRequest<?>>();

        for (String configName : m_configList.getConfigNames()) {
            String configPlugin = m_configList.getConfigPlugin(configName);

            if (configPlugins.add(configPlugin)) {
                GetPropertyRequest getPropertyRequest = constructEditorRequest(
                        m_editorName, configPlugin);

                getPropertyRequest.setCallback(new EditorLoaderCallback(
                        configPlugin));
                requests.add(getPropertyRequest);
            }
        }

        m_requestManager.doRequest(new ChainedCallback() {
                @Override public void onComplete()
                {

                    // We're done!
                    if (m_callback != null) {
                        m_callback.onComplete();
                    }
                }
            }, requests);
    }

    String getImplementedMethod()
    {
        return m_implementedMethod;
    }

    void setCgiRequestProxy(CgiRequestProxy cgiRequestProxy)
    {
        m_cgiRequestProxy = cgiRequestProxy;
    }

    /**
     * Set the editor name. Call this function before calling {@link #load()}.
     *
     * @param  editorName  a property name corresponding to a form defined on a
     *                     per scm plugin basis. Some valid examples include
     *                     sentry, checkout, trigger
     */
    public void setEditorName(String editorName)
    {
        m_editorName = editorName;
    }

    //~ Inner Classes ----------------------------------------------------------

    public class EditorLoaderCallback
        implements PropertyCallback
    {

        //~ Instance fields ----------------------------------------------------

        private String m_configPlugin;

        //~ Constructors -------------------------------------------------------

        public EditorLoaderCallback(String configPlugin)
        {
            m_configPlugin = configPlugin;
        }

        //~ Methods ------------------------------------------------------------

        @Override public void handleError(CommanderError error)
        {

            if (m_component instanceof HasErrorPanel) {
                ((HasErrorPanel) m_component).addErrorMessage(error);
            }
            else {
                m_component.getLog()
                           .error(error);
            }
        }

        @Override public void handleResponse(Property response)
        {

            if (m_component.getLog()
                           .isDebugEnabled()) {
                m_component.getLog()
                           .debug("Commander getProperty request returned: "
                               + response);
            }

            if (response != null) {
                String value = response.getValue();

                if (!StringUtil.isEmpty(value)) {
                    m_configList.setEditorDefinition(m_configPlugin, value);

                    return;
                }
            }

            // There was no property value found in the response
            String errorMsg = "Editor '" + m_editorName
                    + "' not found for SCM plugin '" + m_configPlugin + "'";

            if (m_component instanceof HasErrorPanel) {
                ((HasErrorPanel) m_component).addErrorMessage(errorMsg);
            }
            else {
                m_component.getLog()
                           .error(errorMsg);
            }
        }
    }
}
