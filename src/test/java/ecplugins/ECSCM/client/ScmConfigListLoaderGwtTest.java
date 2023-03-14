
// ScmConfigListLoaderTest.java --
//
// ScmConfigListLoaderTest.java is part of ElectricCommander.
//
// Copyright (c) 2005-2010 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.impl.PropertyImpl;
import com.electriccloud.commander.gwt.client.protocol.json.CommanderObjectImpl;
import com.electriccloud.commander.gwt.client.protocol.json.JsonWrapper;
import com.electriccloud.commander.gwt.client.test.CommanderRequestManagerTestImpl;
import com.electriccloud.commander.client.util.StringUtil;

import ecinternal.client.test.FakeCgiRequestProxy;

import static ecplugins.ECSCM.client.ScmConfigListLoader.constructEditorRequestId;

public class ScmConfigListLoaderGwtTest
    extends ScmConfigListLoaderTestBase
{

    //~ Instance fields --------------------------------------------------------

    private ComponentBase                   m_queryObject;
    private CommanderRequestManagerTestImpl m_requestManager;
    private FakeCgiRequestProxy             m_cgiRequestProxy;
    private ScmConfigList                   m_configList;

    //~ Methods ----------------------------------------------------------------

    @Override public void gwtSetUp()
    {
        m_queryObject = new ComponentBase() {
            @Override public Widget doInit()
            {
                return null;
            }
        };
        m_queryObject.setLog(m_uiFactory.createFormattedLogger());
        m_queryObject.setUIFactory(m_uiFactory);
        m_requestManager = new CommanderRequestManagerTestImpl();
        m_queryObject.setRequestManager(m_requestManager);
        m_cgiRequestProxy = new FakeCgiRequestProxy("ECSCM", "ecscm.cgi");
        m_configList      = new ScmConfigList();
    }

    public void testLoad_getCfgList()
    {

        // Initialize the loader
        ScmConfigListLoader loader = new ScmConfigListLoader(m_configList,
                m_queryObject, null);

        loader.setCgiRequestProxy(m_cgiRequestProxy);

        // Set the CGI response
        String requestId = constructCgiRequestId(loader);

        m_cgiRequestProxy.addResponse(requestId, s_goodResponse);

        // Issue the load request
        loader.load();

        // Check issued CGI requests
        assertEquals(1, m_cgiRequestProxy.getIssuedRequests()
                                         .size());

        Map<String, String> params = new HashMap<String, String>();

        params.put("cmd", "getCfgList");
        assertEquals(requestId, m_cgiRequestProxy.getIssuedRequests()
                                                 .get(0));

        // Check config list
        Set<String> configNames = m_configList.getConfigNames();

        assertNotNull(configNames);
        assertEquals(3, configNames.size());
        assertTrue(configNames.contains("config1"));
        assertTrue(configNames.contains("config2"));
        assertTrue(configNames.contains("config3"));
    }

    public void testLoad_getImplementingCfgs()
    {

        // Initialize the loader
        String              method = "foo";
        ScmConfigListLoader loader = new ScmConfigListLoader(m_configList,
                method, m_queryObject, null);

        loader.setCgiRequestProxy(m_cgiRequestProxy);

        // Set the CGI response
        String requestId = constructCgiRequestId(loader);

        m_cgiRequestProxy.addResponse(requestId, s_goodResponse);

        // Issue the load request
        loader.load();

        // Check issued CGI requests
        assertEquals(1, m_cgiRequestProxy.getIssuedRequests()
                                         .size());

        Map<String, String> params = new HashMap<String, String>();

        params.put("cmd", "getImplementingCfgs");
        params.put("method", method);
        assertEquals(requestId, m_cgiRequestProxy.getIssuedRequests()
                                                 .get(0));

        // Check config list
        Set<String> configNames = m_configList.getConfigNames();

        assertNotNull(configNames);
        assertEquals(3, configNames.size());
        assertTrue(configNames.contains("config1"));
        assertTrue(configNames.contains("config2"));
        assertTrue(configNames.contains("config3"));
    }

    public void testLoad_withEditors()
    {

        // Initialize the loader
        ScmConfigListLoader loader     = new ScmConfigListLoader(m_configList,
                m_queryObject, null);
        String              editorName = "bar";

        loader.setEditorName(editorName);
        loader.setCgiRequestProxy(m_cgiRequestProxy);

        // Set the CGI response
        String cgiRequestId = constructCgiRequestId(loader);

        m_cgiRequestProxy.addResponse(cgiRequestId, s_goodResponse);

        // Issue the load request
        loader.load();

        // Set the Commander responses
        String   requestId = constructEditorRequestId("pluginA");
        Property response  = constructGetPropertyResponse(editorName,
                s_editorDefinitionA);

        m_requestManager.callCallback(requestId, response);
        requestId = constructEditorRequestId("pluginB");
        response  = constructGetPropertyResponse(editorName,
                s_editorDefinitionB);

        m_requestManager.callCallback(requestId, response);

        // Check issued CGI requests
        assertEquals(1, m_cgiRequestProxy.getIssuedRequests()
                                         .size());

        Map<String, String> params = new HashMap<String, String>();

        params.put("cmd", "getCfgList");
        assertEquals(cgiRequestId,
            m_cgiRequestProxy.getIssuedRequests()
                             .get(0));

        // Check issued Commander requests
        List<String> requests = m_requestManager.getIssuedRequests();

        assertNotNull(requests);
        assertEquals(1, requests.size());

//        String expectedRequest = "<requests>"
//            + constructEditorRequest(editorName, "pluginA")
//            + constructEditorRequest(editorName, "pluginB")
//            + "</requests>";
//
//        assertEquals(expectedRequest, requests.get(0));
        // Check config list
        Set<String> configNames = m_configList.getConfigNames();

        assertNotNull(configNames);
        assertEquals(3, configNames.size());
        assertTrue(configNames.contains("config1"));
        assertTrue(configNames.contains("config2"));
        assertTrue(configNames.contains("config3"));

        // Check editors
        assertEquals(s_editorDefinitionA,
            m_configList.getEditorDefinition("config1"));
        assertEquals(s_editorDefinitionA,
            m_configList.getEditorDefinition("config2"));
        assertEquals(s_editorDefinitionB,
            m_configList.getEditorDefinition("config3"));
    }

    private static String constructCgiRequestId(ScmConfigListLoader loader)
    {
        String method = loader.getImplementedMethod();
        String cmd    = StringUtil.isEmpty(method)
            ? "getCfgList"
            : "getImplementingCfgs";

        return FakeCgiRequestProxy.constructCgiRequestId(cmd, method);
    }

    private static Property constructGetPropertyResponse(
            String propName,
            String value)
    {
        Property p = new PropertyImpl(new CommanderObjectImpl(new JsonWrapper()
                        .put("propertyName", propName)
                        .put("value", value)));

        return p;
    }
}
