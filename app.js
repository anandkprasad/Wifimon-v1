var express = require("express");
var bodyParser = require("body-parser");
var mongoose = require("mongoose");
var LocalStrategy = require("passport-local");
var passportLocalMongoose = require("passport-local-mongoose");
var flash = require("connect-flash");
var passport = require("passport");

//ssh
var { Client } = require('ssh2');

var homeRoute = require("./routes/Home.js");

var app = express();

mongoose.connect('mongodb://localhost/wifimon', {});
app.use(express.static('public'));
app.use(bodyParser.json({ limit: "2mb" }));
app.use(bodyParser.urlencoded({ limit: "2mb", extended: true }));

//Schema (will refactor later)
var userSchema = new mongoose.Schema({
    username: String,
    password: String,
});

userSchema.plugin(passportLocalMongoose);

var User = mongoose.model("User", userSchema);

var monSchema = new mongoose.Schema({
    timestamp: String,
    src_ip: String,
    dest_ip: String,
    query_type: String,
    domain: String
});

var Mon = mongoose.model("Mon", monSchema);

//PASSPORT CONFIG
app.use(require('express-session')({
    secret: "I can do it!",
    resave: false,
    saveUninitialized: false
}));
app.use(passport.initialize());
app.use(passport.session());
passport.use(new LocalStrategy(User.authenticate()));
passport.serializeUser(User.serializeUser());
passport.deserializeUser(User.deserializeUser());
app.use(flash());


app.use(function (req, res, next) {
    res.locals.currentUser = req.user;
    res.locals.error = req.flash("error");
    res.locals.success = req.flash("success");
    next();
});

isLoggedIn = function (req, res, next) {
    if (req.isAuthenticated()) {
        return next();
    }
    req.flash("error", "Please Login first!");
    res.redirect("/");
}

app.get("/", homeRoute);

//Monitoring using GUI

const sshConfig = {
    host: '192.168.99.1',  // OpenWrt IP
    port: 22, 
    username: 'root',
    password: ''  // Use SSH key-based auth for security
};

const scriptPath = "/scripts/mon.sh";  // Path to your script


// Start script
app.get('/start', (req, res) => {
    const conn = new Client();
    conn.on('ready', () => {
        console.log('SSH Connection Established');
        conn.exec("sh /scripts/mon.sh", (err, stream) => {
            if (err) return res.status(500).send('Error starting script');
            
            res.send('Script started!');

            stream.on('close', () => {
                console.log('Script started with PID:', output.trim());
                conn.end();
            });
        });
    }).connect(sshConfig);
});



// Stop script
app.get('/stop', (req, res) => {
    const conn = new Client();
    conn.on('ready', () => {
        console.log('SSH Connection Established');
        conn.exec('killall sh', (err, stream) => {
            if (err) return res.status(500).send('Error stopping script');

            res.send('Script stopped!');

            stream.on('close', () => {
                console.log('Script stopped');
                conn.end();
            });
        });
    }).connect(sshConfig);
});



app.get("/getCon", isLoggedIn, function (req, res) {
    const conn = new Client();
    conn.on("ready", () => {
        console.log("SSH Connection Established");

        conn.exec("iwinfo phy0-ap0 assoclist", (err, stream) => {
            if (err) return res.status(500).json({ error: "SSH command execution failed" });

            let dataBuffer = "";

            stream.on("data", (chunk) => {
                dataBuffer += chunk.toString();
            });

            stream.on("close", () => {
                console.log("Raw Output:\n", dataBuffer); // Debugging

                // Fetch DHCP leases for hostname lookup
                conn.exec("cat /tmp/dhcp.leases", (err, leaseStream) => {
                    if (err) {
                        conn.end();
                        return res.status(500).json({ error: "Failed to retrieve DHCP leases" });
                    }

                    let leaseBuffer = "";

                    leaseStream.on("data", (chunk) => {
                        leaseBuffer += chunk.toString();
                    });

                    leaseStream.on("close", () => {
                        const parseData = (raw, leases) => {
                            const hostnameMap = {};
                            leases.split("\n").forEach((line) => {
                                const parts = line.split(/\s+/);
                                if (parts.length >= 4) {
                                    const mac = parts[1].toUpperCase();
                                    const hostname = parts[3] !== "*" ? parts[3] : "Unknown";
                                    hostnameMap[mac] = hostname;
                                }
                            });

                            const devices = [];
                            const blocks = raw.trim().split(/\n\s*\n/); // Splitting devices by empty lines

                            blocks.forEach((block) => {
                                const lines = block.split("\n").map((line) => line.trim()); // Trim all lines

                                const firstLine = lines[0].match(
                                    /^([A-F0-9:]+)\s+(-?\d+)\s+dBm\s+\/\s+(-?\d+)\s+dBm\s+\(SNR\s+(\d+)\)\s+(\d+)\s+ms\s+ago/
                                );

                                if (!firstLine) return;

                                const mac = firstLine[1];
                                const device = {
                                    mac: mac,
                                    hostname: hostnameMap[mac] || "Unknown",  // Lookup hostname
                                    signal: {
                                        current: parseInt(firstLine[2], 10),
                                        noise: parseInt(firstLine[3], 10),
                                        snr: parseInt(firstLine[4], 10),
                                        lastSeenMs: parseInt(firstLine[5], 10),
                                    },
                                    rx: {},
                                    tx: {},
                                };

                                lines.slice(1).forEach((line) => {
                                    const rxMatch = line.match(/RX:\s+([\d.]+)\s+MBit\/s,\s+VHT-MCS\s+(\d+),\s+(\d+)MHz,\s+VHT-NSS\s+(\d+)\s+(\d+)\s+Pkts\./);
                                    const txMatch = line.match(/TX:\s+([\d.]+)\s+MBit\/s,\s+VHT-MCS\s+(\d+),\s+(\d+)MHz,\s+VHT-NSS\s+(\d+)\s+(\d+)\s+Pkts\./);

                                    if (rxMatch) {
                                        device.rx = {
                                            rate: parseFloat(rxMatch[1]),
                                            mcs: parseInt(rxMatch[2], 10),
                                            bandwidth: parseInt(rxMatch[3], 10),
                                            nss: parseInt(rxMatch[4], 10),
                                            packets: parseInt(rxMatch[5], 10),
                                        };
                                    }

                                    if (txMatch) {
                                        device.tx = {
                                            rate: parseFloat(txMatch[1]),
                                            mcs: parseInt(txMatch[2], 10),
                                            bandwidth: parseInt(txMatch[3], 10),
                                            nss: parseInt(txMatch[4], 10),
                                            packets: parseInt(txMatch[5], 10),
                                        };
                                    }
                                });

                                devices.push(device);
                            });

                            return JSON.stringify(devices, null, 2);
                        };

                        res.render("dev.ejs", { data: parseData(dataBuffer, leaseBuffer) });
                        conn.end();
                    });
                });
            });
        });
    }).connect({
        host: "192.168.99.1",
        username: "root",
        password: "",
    });
});



app.get("/signup", function (req, res) {
    res.render("signup.ejs");
});

app.get("/dashboard", isLoggedIn, function (req, res) {
    Mon.find({}).then(function (mons) {
        res.render("dashboard.ejs", { mons: mons });
    })
});

app.get("/logout", function (req, res) {
    req.logOut(function () {
        req.flash("success", "Successfully logged out!");
        res.redirect("/");
    });
});


app.post("/mon", function (req, res) {
    req.body.forEach(element => {
        var newMon = new Mon({
            timestamp: element.timestamp,
            src_ip: element.src_ip,
            dest_ip: element.dest_ip,
            query_type: element.query_type,
            domain: element.domain
        });

        Mon.create(newMon);
    });
    res.redirect("/dashboard");
});

app.post("/login", passport.authenticate("local", {
    successRedirect: "/dashboard",
    failureRedirect: "/",
    failureFlash: true
}), function (req, res) {
});


app.post("/signup", function (req, res) {
    User.register(new User({
        username: req.body.username,
    }), req.body.password, function (err, user) {
        if (err) {
            req.flash("error", err.message);
            console.log(err);
            res.redirect("/");
        }
        passport.authenticate("local")(req, res, function () {
            res.redirect("/dashboard");
        });
    });
})

var port = 3000;

app.listen(port, function () {
    console.log("Server is running on port 3000!");
})