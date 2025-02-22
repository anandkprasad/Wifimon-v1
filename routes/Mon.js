
function monRoute(req, res){
    res.send("Mon Route hit successfully from openwrt!");
    console.log(req.body);
}

module.exports = monRoute