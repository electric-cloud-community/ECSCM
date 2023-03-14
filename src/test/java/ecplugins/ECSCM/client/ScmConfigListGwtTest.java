
// ScmConfigListTest.java --
//
// ScmConfigListTest.java is part of ElectricCommander.
//
// Copyright (c) 2005-2010 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.Set;

import com.electriccloud.commander.gwt.client.ui.ValuedListBox;

public class ScmConfigListGwtTest
    extends ScmConfigListLoaderTestBase
{

    //~ Instance fields --------------------------------------------------------

    private ScmConfigList m_configList;

    //~ Methods ----------------------------------------------------------------

    @Override public void gwtSetUp()
    {
        m_configList = new ScmConfigList();
    }

    public void testAddConfig()
    {

        // Add a test config
        String configName   = "testConfig";
        String configPlugin = "testPlugin";
        String configDesc   = "testPlugin configuration";

        m_configList.addConfig(configName, configPlugin, configDesc);

        // Check list size
        Set<String> configNames = m_configList.getConfigNames();

        assertNotNull(configNames);
        assertEquals(1, configNames.size());

        // Check testConfig
        assertTrue(configNames.contains(configName));
        assertEquals(configPlugin, m_configList.getConfigPlugin(configName));
        assertEquals(configDesc, m_configList.getConfigDescription(configName));
    }

    public void testGetSetEditorDefiniton()
    {

        // Parse the good response, then set an editor definition
        String error = m_configList.parseResponse(s_goodResponse);

        assertNull(error);
        m_configList.setEditorDefinition("pluginA", s_editorDefinitionA);

        // Check the editor definition for each config
        assertEquals(s_editorDefinitionA,
            m_configList.getEditorDefinition("config1"));
        assertEquals(s_editorDefinitionA,
            m_configList.getEditorDefinition("config2"));
        assertNull(m_configList.getEditorDefinition("config3"));
    }

    public void testIsEmpty()
    {

        // Make sure the list is empty
        assertTrue(m_configList.isEmpty());

        // Add a config, then make sure the list is no longer empty
        m_configList.addConfig("foo", "bar", "baz");
        assertFalse(m_configList.isEmpty());
    }

    public void testParseResponse_bad()
    {

        // Parse an error response
        String error = m_configList.parseResponse(s_errorResponse);

        assertNotNull(error);
        assertEquals("There was an error.", error);
    }

    public void testParseResponse_good()
    {

        // Parse a good response
        String error = m_configList.parseResponse(s_goodResponse);

        assertNull(error);

        // Check list size
        Set<String> configNames = m_configList.getConfigNames();

        assertNotNull(configNames);
        assertEquals(3, configNames.size());

        // Check config1
        String configName = "config1";

        assertTrue(configNames.contains(configName));
        assertEquals("pluginA", m_configList.getConfigPlugin(configName));
        assertEquals("pluginA configuration",
            m_configList.getConfigDescription(configName));

        // Check config2
        configName = "config2";
        assertTrue(configNames.contains(configName));
        assertEquals("pluginA", m_configList.getConfigPlugin(configName));
        assertEquals("Another pluginA configuration",
            m_configList.getConfigDescription(configName));

        // Check config3
        configName = "config3";
        assertTrue(configNames.contains(configName));
        assertEquals("pluginB", m_configList.getConfigPlugin(configName));
        assertEquals("pluginB configuration",
            m_configList.getConfigDescription(configName));
    }

    public void testPopulateConfigListBox()
    {

        // Parse the good response, then populate a list box
        String error = m_configList.parseResponse(s_goodResponse);

        assertNull(error);

        ValuedListBox lb = m_uiFactory.createValuedListBox();

        m_configList.populateConfigListBox(lb);

        // Check list box
        assertEquals(3, lb.getItemCount());
        assertEquals("config1", lb.getItemText(0));
        assertEquals("config2", lb.getItemText(1));
        assertEquals("config3", lb.getItemText(2));
    }
}
