
// ScmConfigListLoaderTestBase.java --
//
// ScmConfigListLoaderTestBase.java is part of ElectricCommander.
//
// Copyright (c) 2005-2010 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.junit.client.GWTTestCase;

import com.electriccloud.commander.gwt.client.ui.UIFactory;
import com.electriccloud.commander.gwt.client.ui.impl.UIFactoryImpl;

public abstract class ScmConfigListLoaderTestBase
    extends GWTTestCase
{

    //~ Static fields/initializers ---------------------------------------------

    protected static final String s_goodResponse      = "<response>"
            + "  <cfgs>"
            + "    <cfg>"
            + "      <name>config1</name>"
            + "      <plugin>pluginA</plugin>"
            + "      <desc>pluginA configuration</desc>"
            + "    </cfg>"
            + "    <cfg>"
            + "      <name>config2</name>"
            + "      <plugin>pluginA</plugin>"
            + "      <desc>Another pluginA configuration</desc>"
            + "    </cfg>"
            + "    <cfg>"
            + "      <name>config3</name>"
            + "      <plugin>pluginB</plugin>"
            + "      <desc>pluginB configuration</desc>"
            + "    </cfg>"
            + "  </cfgs>"
            + "</response>";
    protected static final String s_errorResponse     = "<response>"
            + "  <error>There was an error.</error>"
            + "</response>";
    protected static final String s_editorDefinitionA = "<editor>"
            + "  <formElement>"
            + "    <type>entry</type>"
            + "    <label>Field #1</label>"
            + "    <property>field1</property>"
            + "    <documentation>The first field of the form</documentation>"
            + "  </formElement>"
            + "  <formElement>"
            + "    <type>textarea</type>"
            + "    <label>Field #2</label>"
            + "    <property>field2</property>"
            + "    <documentation>The second field of the form</documentation>"
            + "  </formElement>"
            + "</editor>";
    protected static final String s_editorDefinitionB = "<editor>"
            + "  <formElement>"
            + "    <type>checkbox</type>"
            + "    <label>Field #1</label>"
            + "    <property>field1</property>"
            + "    <checkedValue>1</checkedValue>"
            + "    <uncheckedValue>0</uncheckedValue>"
            + "    <initiallyChecked>1</initiallyChecked>"
            + "    <documentation>The first field of the form</documentation>"
            + "  </formElement>"
            + "  <formElement>"
            + "    <type>entry</type>"
            + "    <label>Field #2</label>"
            + "    <property>field2</property>"
            + "    <documentation>The second field of the form</documentation>"
            + "  </formElement>"
            + "</editor>";

    //~ Instance fields --------------------------------------------------------

    protected UIFactory m_uiFactory = new UIFactoryImpl();

    //~ Methods ----------------------------------------------------------------

    @Override public String getModuleName()
    {
        return "ecplugins.ECSCM.ScmConfigListLoader";
    }
}
