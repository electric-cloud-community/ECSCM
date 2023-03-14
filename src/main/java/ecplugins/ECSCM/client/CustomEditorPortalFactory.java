
// CustomEditorPortalFactory.java --
//
// CustomEditorPortalFactory.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.http.client.URL;

import ecinternal.client.InternalComponentBaseFactory;

import com.electriccloud.commander.gwt.client.BrowserContext;
import com.electriccloud.commander.gwt.client.Component;
import com.electriccloud.commander.gwt.client.ComponentContext;
import org.jetbrains.annotations.NotNull;

public class CustomEditorPortalFactory
    extends InternalComponentBaseFactory
{

    //~ Methods ----------------------------------------------------------------

    @NotNull
    @Override public Component createComponent(ComponentContext jso)
    {
        String    panel          = jso.getParameter("panel");
        String    propPath       = BrowserContext.getInstance()
                                                 .getObjectContext();
        String[]  propPathTokens = propPath.split("/");
        String    projectName    = URL.decodeQueryString(propPathTokens[2]);
        Component component;

        if ("preflightStep".equals(panel)) {
            String procedureName = URL.decodeQueryString(propPathTokens[4]);

            component = new PreflightPortal(projectName, procedureName);
        }
        else {

            // Default panel is "sentrySchedule"
            component = new SentryPortal(projectName);
        }

        return component;
    }
}
