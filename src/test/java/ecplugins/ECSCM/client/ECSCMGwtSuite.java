
// ECSCMGwtTestSuite.java --
//
// ECSCMGwtTestSuite.java is part of ElectricCommander.
//
// Copyright (c) 2005-2012 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.junit.tools.GWTTestSuite;

import junit.framework.Test;

import com.electriccloud.test.IsGwtTestClass;
import com.electriccloud.test.TestSuiteUtil;

public class ECSCMGwtSuite
    extends GWTTestSuite
{

    //~ Methods ----------------------------------------------------------------

    public static Test suite()
    {
        return TestSuiteUtil.suite(ECSCMGwtSuite.class,
            new IsGwtTestClass());
    }
}
