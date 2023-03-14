
// ConfigPickerImpl.java --
//
// ConfigPickerImpl.java is part of ElectricCommander.
//
// Copyright (c) 2005-2012 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.event.logical.shared.ValueChangeEvent;
import com.google.gwt.event.logical.shared.ValueChangeHandler;
import com.google.gwt.user.client.ui.HasValue;
import com.google.gwt.user.client.ui.SuggestBox;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.CommanderRequestFactory;
import com.electriccloud.commander.client.CommanderRequestManager;
import com.electriccloud.commander.client.domain.ObjectType;
import com.electriccloud.commander.client.requests.FindObjectsFilter;
import com.electriccloud.commander.client.requests.FindObjectsRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.CommanderErrorHandler;
import com.electriccloud.commander.client.responses.FindObjectsResponseCallback;

import ecinternal.client.FindObjectsOptionsListLoader;
import ecinternal.client.FormValue;
import ecinternal.client.FormValueWrapper;
import ecinternal.client.ui.OptionListLoader;
import ecinternal.client.ui.SuggestBoxWrapper;

import static com.electriccloud.commander.gwt.client.util.WidgetUtil.PICKERLIMIT;

public class ConfigPickerImpl
    extends FormValueWrapper
    implements CommanderErrorHandler,
        ConfigPicker,
        ValueChangeHandler<String>
{

    //~ Instance fields --------------------------------------------------------

    private HasValue<String>            m_projectBox;
    private CommanderRequestFactory     m_requestFactory;
    private CommanderRequestManager     m_requestManager;
    private FindObjectsResponseCallback m_configBoxLoader;
    private final FormValue<String>     m_configBox;

    //~ Constructors -----------------------------------------------------------

    public ConfigPickerImpl(CommanderRequestManager requestManager)
    {
        SuggestBox configBox = new SuggestBox();

        configBox.setLimit(PICKERLIMIT - 1);
        setWidget(configBox);
        m_configBox = new FormValueWrapper(configBox);
        setRequestManager(requestManager);
        setOptionLoader(new SuggestBoxWrapper(configBox));
    }

    //~ Methods ----------------------------------------------------------------

    @Override
    @SuppressWarnings({"RefusedBequest"})
    public Widget asWidget()
    {
        return m_configBox.asWidget();
    }

    @Override public void handleError(CommanderError error)
    {
        // TODO
    }

    @Override public void onValueChange(ValueChangeEvent<String> event)
    {
        refreshOptions(m_projectBox.getValue());
    }

    @Override public void refreshOptions(String projectName)
    {
        setValue("", true);

        FindObjectsRequest configBoxRequest = getFindObjectsRequest(
                projectName);

        configBoxRequest.setCallback(m_configBoxLoader);
        m_requestManager.doRequest(configBoxRequest);
    }

    public FindObjectsRequest getFindObjectsRequest(String projectName)
    {
        FindObjectsRequest configBoxRequest =
            m_requestFactory.createFindObjectsRequest(ObjectType.schedule);

        configBoxRequest.addFilter(new FindObjectsFilter.AndFilter(
                new FindObjectsFilter.EqualsFilter("projectName", projectName),
                new FindObjectsFilter.IsNotNullFilter("ec_ci")));

        return configBoxRequest;
    }

    @Override
    @SuppressWarnings({"RefusedBequest"})
    public Widget getWidget()
    {
        return asWidget();
    }

    @Override public final void setOptionLoader(OptionListLoader loader)
    {
        m_configBoxLoader = new FindObjectsOptionsListLoader(this, loader,
                "scheduleName", "schedule");
    }

    @Override public void setProjectBox(HasValue<String> projectBox)
    {
        m_projectBox = projectBox;
        m_projectBox.addValueChangeHandler(this);
    }

    public final void setRequestManager(CommanderRequestManager requestManager)
    {
        m_requestManager = requestManager;
        m_requestFactory = requestManager.getRequestFactory();
    }
}
