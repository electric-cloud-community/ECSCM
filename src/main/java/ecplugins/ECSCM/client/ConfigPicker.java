
// ConfigPicker.java --
//
// ConfigPicker.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.user.client.ui.HasValue;

import ecinternal.client.FormValue;

import ecinternal.client.ui.OptionListLoader;

public interface ConfigPicker
    extends FormValue<String>
{

    //~ Methods ----------------------------------------------------------------

    void refreshOptions(String projectName);

    void setOptionLoader(OptionListLoader loader);

    void setProjectBox(HasValue<String> projectBox);
}
