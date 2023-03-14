import com.electriccloud.query.Filter
import com.electriccloud.query.CompositeFilter
import com.electriccloud.query.PropertyFilter
import com.electriccloud.query.Operator

def procedureName = args.procedureName
def projectName = args.projectName

def procedure = [
    propertyName: 'procedureName',
    operator: 'equals',
    operand1: procedureName
]

def project = [
    propertyName: 'projectName',
    operator: 'equals',
    operand1: projectName
]
def filters = [[operator: 'and', filters: [procedure, project]]]

def result = findObjects(objectType: 'job', filter: constructFilters(filters))
return result

def constructFilters(def filters) {
    filters?.collect {
        def op = Operator.valueOf(it.operator)
        if (op.isBoolean()) {
            assert it.filters
            new CompositeFilter(op, constructFilters(it.filters) as Filter[])
        } else {
            new PropertyFilter(it.propertyName, op, it.operand1, it.operand2)
        }
    }
}