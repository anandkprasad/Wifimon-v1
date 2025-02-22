var express = require("express");
var router = express.Router();

function homeRoute(req, res){
    res.render("home.ejs");
}

module.exports = homeRoute