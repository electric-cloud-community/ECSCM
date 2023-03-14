package com.electriccloud.specs.rcc

import spock.lang.Ignore
import spock.lang.Shared
import spock.lang.Unroll

import com.electriccloud.specs.Helper

class RCCSetup extends Helper {

    def 'plugin metadata exists for create DOIS datasource'() {

        when: 'createDOISDataSource properties are registered'
        def result = dsl "getProperties(path: '/plugins/ECSCM/project/ec_devops_insight/build/operations/createDOISDataSource')"

        then:
        assert result?.propertySheet?.property?.find{it.propertyName == 'ec_parameterForm'}
        assert result?.propertySheet?.property?.find{it.propertyName == 'script'}
        assert result?.propertySheet?.property?.find{
            it.propertyName == 'procedureName' &&
            it.value == '_DOISDataSourceHelper'}

    }

    def 'plugin metadata exists for delete DOIS datasource'() {

        when: 'createDOISDataSource properties are registered'
        def result = dsl "getProperties(path: '/plugins/ECSCM/project/ec_devops_insight/build/operations/deleteDOISDataSource')"

        then:
        // no form xml property is expected to be registered for delete
        assert result?.propertySheet?.property?.find{it.propertyName == 'ec_parameterForm'} == null
        assert result?.propertySheet?.property?.find{it.propertyName == 'script'}

    }

    def 'plugin metadata exists for modify DOIS datasource'() {

        when: 'createDOISDataSource properties are registered'
        def result = dsl "getProperties(path: '/plugins/ECSCM/project/ec_devops_insight/build/operations/modifyDOISDataSource')"

        then:
        assert result?.propertySheet?.property?.find{it.propertyName == 'ec_parameterForm'}
        assert result?.propertySheet?.property?.find{it.propertyName == 'script'}
        assert result?.propertySheet?.property?.find{
            it.propertyName == 'procedureName' &&
            it.value == '_DOISDataSourceHelper'}

    }

    def 'procedure metadata exists the dois helper procedure'() {

        when:
        def proc = dsl "getProcedure(projectName: '/plugins/ECSCM/project', procedureName: '_DOISDataSourceHelper')"
        def propId = proc?.procedure?.propertySheetId
        def result = dsl "getProperties(propertySheetId: '$propId', recurse: true)"

        then:
        assert result?.propertySheet?.property?.find{it.propertyName == 'ec_form'}?.
                propertySheet?.property?.find{it.propertyName == 'parameterOptions'}?.
                propertySheet?.property?.find{
                    it.propertyName == 'ciScheduleName' && it.value}
    }

    def 'plugin metadata exists for icon'() {

        when: 'icon property is also registered'
        def result = dsl "getProperty(propertyName: '/plugins/ECSCM/project/ec_icon')"

        then:
        assert result?.property?.value == 'images/icon-plugin.svg'
    }

    def 'plugin metadata exists for source'() {

        when: 'build source is registered'
        def result = dsl "getProperty('/plugins/ECSCM/project/ec_devops_insight/build/source')"

        then:
        assert result?.property?.value == 'CloudBees CD'

    }

}
