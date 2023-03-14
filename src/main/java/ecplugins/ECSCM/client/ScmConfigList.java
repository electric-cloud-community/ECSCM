
// ScmConfigList.java --
//
// ScmConfigList.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import com.google.gwt.xml.client.Document;
import com.google.gwt.xml.client.Node;
import com.google.gwt.xml.client.XMLParser;

import com.electriccloud.commander.gwt.client.ui.ValuedListBox;

import static com.electriccloud.commander.gwt.client.util.XmlUtil.getNodeByName;
import static com.electriccloud.commander.gwt.client.util.XmlUtil.getNodeValueByName;
import static com.electriccloud.commander.gwt.client.util.XmlUtil.getNodesByName;

/**
 * Class that represents a list of Source Code Configurations(SCMs).
 */
public class ScmConfigList
{

    //~ Instance fields --------------------------------------------------------

    private final Map<String, ScmConfigInfo> m_configInfo        =
        new TreeMap<String, ScmConfigInfo>();
    private final Map<String, String>        m_editorDefinitions =
        new HashMap<String, String>();

    //~ Methods ----------------------------------------------------------------

    public void addConfig(
            String configName,
            String configPlugin,
            String configDesc)
    {
        m_configInfo.put(configName,
            new ScmConfigInfo(configPlugin, configDesc));
    }

    public String parseResponse(String cgiResponse)
    {
        Document document     = XMLParser.parse(cgiResponse);
        Node     responseNode = getNodeByName(document, "response");
        String   error        = getNodeValueByName(responseNode, "error");

        if (error != null && !error.isEmpty()) {
            return error;
        }

        Node       configListNode = getNodeByName(responseNode, "cfgs");
        List<Node> configNodes    = getNodesByName(configListNode, "cfg");

        for (Node configNode : configNodes) {
            String configName   = getNodeValueByName(configNode, "name");
            String configPlugin = getNodeValueByName(configNode, "plugin");
            String configDesc   = getNodeValueByName(configNode, "desc");

            addConfig(configName, configPlugin, configDesc);
        }

        return null;
    }

    public void populateConfigListBox(ValuedListBox lb)
    {

        for (String configName : m_configInfo.keySet()) {
            lb.addItem(configName);
        }
    }

    public String getConfigDescription(String configName)
    {
        return m_configInfo.get(configName).m_description;
    }

    public Set<String> getConfigNames()
    {
        return m_configInfo.keySet();
    }

    /**
     * Returns the plugin name corresponding to an SCM configuration type.
     *
     * @param   configName  a scm configuration name
     *
     * @return  the plugin name corresponding to the scm configuration type
     */
    public String getConfigPlugin(String configName)
    {
        return m_configInfo.get(configName).m_plugin;
    }

    /**
     * Gets a XML form representation that has been defined for a particular SCM
     * type. For use with {@link
     * com.electriccloud.commander.gwt.client.ui.FormBuilder#addRowsWithXml(String)
     * }
     *
     * @param   configName  a valid SCM configuration name on the commander
     *                      system
     *
     * @return  a form XML definition
     */
    public String getEditorDefinition(String configName)
    {
        return m_editorDefinitions.get(m_configInfo.get(configName).m_plugin);
    }

    public boolean isEmpty()
    {
        return m_configInfo.isEmpty();
    }

    /**
     * @param  configPlugin     a plugin name corresponding to a scm type
     * @param  editorDefiniton  a form xml definition
     */
    public void setEditorDefinition(
            String configPlugin,
            String editorDefiniton)
    {
        m_editorDefinitions.put(configPlugin, editorDefiniton);
    }

    //~ Inner Classes ----------------------------------------------------------

    /**
     * Additional information stored for each SCM Configuration.
     */
    private class ScmConfigInfo
    {

        //~ Instance fields ----------------------------------------------------

        private String m_plugin;
        private String m_description;

        //~ Constructors -------------------------------------------------------

        public ScmConfigInfo(
                String plugin,
                String description)
        {
            m_plugin      = plugin;
            m_description = description;
        }
    }
}
