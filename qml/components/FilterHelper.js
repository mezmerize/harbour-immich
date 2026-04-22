.pragma library

function filterByField(model, filterText, fieldName) {
    if (!filterText || filterText.length === 0) return model
    var lowerFilter = filterText.toLowerCase()
    var result = []
    for (var i = 0; i < model.length; i++) {
        var value = model[i][fieldName] || ""
        if (value.toLowerCase().indexOf(lowerFilter) !== -1) result.push(model[i])
    }
    return result
}
