
// CICheckoutParameterPanel.java --
//
// CICheckoutParameterPanel.java is part of ElectricCommander.
//
// Copyright (c) 2005-2012 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;

import com.google.gwt.core.client.GWT;
import com.google.gwt.user.client.ui.TextBox;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.domain.ActualParameter;
import com.electriccloud.commander.client.domain.FormalParameter;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.ui.ParameterPanel;
import com.electriccloud.commander.gwt.client.ui.ParameterPanelProvider;

import ecinternal.client.InternalComponentBase;

import static ecplugins.ECSCM.client.CICheckoutConstants.CI_CHECKOUT_PARAM_CONFIGURATION;
import static ecplugins.ECSCM.client.CICheckoutConstants.CI_CHECKOUT_PARAM_PREFLIGHT;
import static ecplugins.ECSCM.client.CICheckoutConstants.CI_CHECKOUT_PARAM_PROJECT;

public class CICheckoutParameterPanel
    extends InternalComponentBase
    implements ParameterPanel,
        ParameterPanelProvider
{

    //~ Static fields/initializers ---------------------------------------------

    /**
     * Form row IDs. NB: These are also the CICheckout procedure parameter names
     * and must stay in sync with the procedure formal parameter names in
     * ECSCM:ciCheckout
     */
    static final String         ROWID_PROJECT_NAME       =
        CI_CHECKOUT_PARAM_PROJECT;
    static final String         ROWID_CONFIGURATION_NAME =
        CI_CHECKOUT_PARAM_CONFIGURATION;
    static final String         ROWID_PREFLIGHT          =
        CI_CHECKOUT_PARAM_PREFLIGHT;
    private static final String MY_JOB_PREFIX            = "$[/myJob/";
    private static final String MY_JOB_SUFFIX            = "]";

    //~ Instance fields --------------------------------------------------------

    private CICheckoutResources m_resources;
    private CICheckoutMessages  m_messages;
    private FormTable           m_form;
    private Map<String, String> m_actualParams;

    /** Form elements. */
    private TextBox m_projectPicker;
    private TextBox m_configPicker;
    private TextBox m_preflight;

    //~ Methods ----------------------------------------------------------------

    @Override public Widget doInit()
    {
        m_form = getUIFactory().createFormTable();
        m_form.asWidget()
              .addStyleName(getResources().css()
                                          .ciCheckoutForm());

        CICheckoutStyles css = getResources().css();

        // Project picker
        m_projectPicker = new TextBox();
        m_projectPicker.setValue(MY_JOB_PREFIX + CI_CHECKOUT_PARAM_PROJECT
                + MY_JOB_SUFFIX);
        getForm().addFormRow(ROWID_PROJECT_NAME, getMessages().projectLabel(),
            m_projectPicker, false, getMessages().projectDesc());

        // Config picker
        m_configPicker = new TextBox();
        m_configPicker.setValue(MY_JOB_PREFIX + CI_CHECKOUT_PARAM_CONFIGURATION
                + MY_JOB_SUFFIX);
        getForm().addFormRow(ROWID_CONFIGURATION_NAME,
            getMessages().configLabel(), m_configPicker, false,
            getMessages().configDesc());

        // Preflight
        m_preflight = new TextBox();
        m_preflight.setValue(MY_JOB_PREFIX + CI_CHECKOUT_PARAM_PREFLIGHT
                + MY_JOB_SUFFIX);
        getForm().addFormRow(ROWID_PREFLIGHT, getMessages().preflightLabel(),
            m_preflight, false, getMessages().preflightDesc());

        return m_form.asWidget();
    }

    @Override public boolean validate()
    {

        // None of the parameters are required; each formal parameter of the
        // CICheckout procedure has a default.
        return true;
    }

    Map<String, String> getActualParams()
    {
        return m_actualParams;
    }

    /**
     * For testing.
     *
     * @return
     */
    TextBox getConfig()
    {
        return m_configPicker;
    }

    FormTable getForm()
    {
        return m_form;
    }

    CICheckoutMessages getMessages()
    {

        if (m_messages == null) {
            m_messages = GWT.create(CICheckoutMessages.class);
        }

        return m_messages;
    }

    @Override public ParameterPanel getParameterPanel()
    {
        return this;
    }

    /**
     * For testing.
     *
     * @return
     */
    TextBox getPreflight()
    {
        return m_preflight;
    }

    /**
     * For testing.
     *
     * @return
     */
    TextBox getProject()
    {
        return m_projectPicker;
    }

    CICheckoutResources getResources()
    {

        if (m_resources == null) {
            m_resources = GWT.create(CICheckoutResources.class);
            m_resources.css()
                       .ensureInjected();
        }

        return m_resources;
    }

    @Override public Map<String, String> getValues()
    {
        Map<String, String> values = new HashMap<String, String>();

        values.put(ROWID_PROJECT_NAME, m_projectPicker.getValue());
        values.put(ROWID_CONFIGURATION_NAME, m_configPicker.getValue());
        values.put(ROWID_PREFLIGHT, m_preflight.getValue());

        return values;
    }

    @Override public void setActualParameters(
            Collection<ActualParameter> actualParameters)
    {

        // Store actual params into a hash for easy retrieval later
        m_actualParams = new HashMap<String, String>();

        for (ActualParameter actualParameter : actualParameters) {
            m_actualParams.put(actualParameter.getName(),
                actualParameter.getValue());
        }

        // Update the UI elements with the values from the actual parameters

        // Project
        String projectName = m_actualParams.get(ROWID_PROJECT_NAME);

        if (projectName != null) {
            m_projectPicker.setValue(projectName);
        }

        // Config
        String configName = m_actualParams.get(ROWID_CONFIGURATION_NAME);

        if (configName != null) {
            m_configPicker.setValue(configName);
        }

        // Preflight
        String preflight = m_actualParams.get(ROWID_PREFLIGHT);

        if (preflight != null) {
            m_preflight.setValue(preflight);
        }
    }

    @Override public void setFormalParameters(
            Collection<FormalParameter> formalParameters)
    {
        // We don't care about the formals
    }
}
