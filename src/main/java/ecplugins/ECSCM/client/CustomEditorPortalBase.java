
// CustomEditorPortalBase.java --
//
// CustomEditorPortalBase.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.user.client.ui.HasValue;
import com.google.gwt.user.client.ui.TextBox;

import ecinternal.client.InternalFormBase;

import com.electriccloud.commander.client.ChainedCallback;
import com.electriccloud.commander.gwt.client.ui.FormBuilder;
import com.electriccloud.commander.gwt.client.ui.ValuedListBox;

public abstract class CustomEditorPortalBase
    extends InternalFormBase
{

    //~ Static fields/initializers ---------------------------------------------

    private static final String OBJECT_NAME_KEY         = "objectName";
    private static final String SCM_CONFIGURATION_KEY   = "scmConfig";
    private static final String SCM_CONFIGURATION_LABEL = "SCM Configuration";

    //~ Instance fields --------------------------------------------------------

    private String           m_objectNameLabel;
    private String           m_scmImplementedMethod;
    private ScmConfigList    m_configList;
    private HasValue<String> m_objectNameElement;
    private ValuedListBox    m_configurationTypeElement;

    //~ Constructors -----------------------------------------------------------

    protected CustomEditorPortalBase(
            String idPrefix,
            String formTitle,
            String objectNameLabel,
            String scmImplementedMethod)
    {
        super(idPrefix, formTitle);
        m_objectNameLabel      = objectNameLabel;
        m_scmImplementedMethod = scmImplementedMethod;
        m_configList           = new ScmConfigList();
    }

    //~ Methods ----------------------------------------------------------------

    protected abstract String constructFinalRedirectToUrl();

    protected abstract String constructFormTypeValue();

    protected abstract String constructObjectPropertyPath();

    /**
     * @return                 the initialized FormTable.
     *
     * @wbp.parser.entryPoint
     */
    @Override protected FormBuilder initializeFormTable()
    {
        FormBuilder formBuilder = getUIFactory().createFormBuilder();

        m_objectNameElement = new TextBox();

        // Add rows for the object name and SCM configuration selection
        formBuilder.addRow(true, m_objectNameLabel + ":",
            getUIFactory().getInlineHelpMessages().systemObjectName(),
            OBJECT_NAME_KEY,
            null, m_objectNameElement);
        m_configurationTypeElement = getUIFactory().createValuedListBox();
        formBuilder.addRow(true, SCM_CONFIGURATION_LABEL + ":",
            getUIFactory().getInlineHelpMessages().scmConfiguration(),
            SCM_CONFIGURATION_KEY, null, m_configurationTypeElement);

        return formBuilder;
    }

    @Override protected void load()
    {
        setStatus("Loading...");

        ScmConfigListLoader loader = new ScmConfigListLoader(m_configList,
                m_scmImplementedMethod, this, new ChainedCallback() {
                    @Override public void onComplete()
                    {
                        m_configList.populateConfigListBox(
                            m_configurationTypeElement);

                        // Select the first option by default
                        if (m_configurationTypeElement.getItemCount() > 0) {
                            String firstOption =
                                m_configurationTypeElement.getItemText(0);

                            m_configurationTypeElement.setValue(firstOption);
                        }

                        // Clear the status now that loading is complete
                        clearStatus();
                    }
                });

        loader.load();
    }

    protected ScmConfigList getConfigList()
    {
        return m_configList;
    }

    protected String getObjectNameValue()
    {
        return m_objectNameElement.getValue();
    }

    protected String getScmConfigValue()
    {
        return m_configurationTypeElement.getValue();
    }
}
