
// CICheckoutFactory.java --
//
// CICheckoutFactory.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import ecinternal.client.InternalComponentBaseFactory;

import com.electriccloud.commander.gwt.client.Component;
import com.electriccloud.commander.gwt.client.ComponentContext;
import org.jetbrains.annotations.NotNull;

public class CICheckoutFactory
    extends InternalComponentBaseFactory
{

    //~ Methods ----------------------------------------------------------------

    @NotNull
    @Override protected Component createComponent(ComponentContext jso)
    {
        return new CICheckoutParameterPanel();
    }
}
