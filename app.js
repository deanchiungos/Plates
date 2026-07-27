var confirmAction = null;




  
function hideConfirmSheet() {

  var overlay =
    document.getElementById(
      "confirmOverlay"
    );

  if(overlay) {
    overlay.classList.add(
      "hidden"
    );
  }

  confirmAction = null;
}


  function showConfirmSheet(options) {

  var overlay =
    document.getElementById(
      "confirmOverlay"
    );

  var icon =
    document.getElementById(
      "confirmIcon"
    );

  var title =
    document.getElementById(
      "confirmTitle"
    );

  var tripNameText =
    document.getElementById(
      "confirmTripName"
    );

  var message =
    document.getElementById(
      "confirmMessage"
    );

  var primaryBtn =
    document.getElementById(
      "confirmPrimaryBtn"
    );

  var cancelBtn =
    document.getElementById(
      "confirmCancelBtn"
    );

  if(
    !overlay ||
    !icon ||
    !title ||
    !tripNameText ||
    !message ||
    !primaryBtn ||
    !cancelBtn
  ){
    return;
  }

  icon.textContent =
    options.icon || "✓";

  title.textContent =
    options.title || "Are You Sure?";

  tripNameText.textContent =
    options.tripName || "";

  message.textContent =
    options.message || "";

  primaryBtn.textContent =
    options.buttonText || "Continue";

  primaryBtn.classList.remove(
    "dangerConfirmBtn"
  );

  if(options.danger){
    primaryBtn.classList.add(
      "dangerConfirmBtn"
    );
  }

  confirmAction =
    typeof options.onConfirm === "function"
      ? options.onConfirm
      : null;

  primaryBtn.onclick =
    function(){

      var action =
        confirmAction;

      hideConfirmSheet();

      if(action){
        action();
      }

    };

  cancelBtn.onclick =
    function(){

      hideConfirmSheet();

    };

  overlay.onclick =
    function(e){

      if(e.target === overlay){

        hideConfirmSheet();

      }

    };

  overlay.classList.remove(
    "hidden"
  );

}
  
  
function safeParse(value, fallback) {
  try {
    if (typeof value === "object" && value !== null) {
      return value;
    }

    if (!value || value === "undefined" || value === "[object Object]") {
      return JSON.parse(fallback);
    }

    return JSON.parse(value);
  } catch(e) {
    console.log("Bad JSON:", value);
    return JSON.parse(fallback);
  }
}
var onboardingDone =
  document.getElementById(
    "onboardingDone"
  );

if(onboardingDone){

  onboardingDone.onclick =
    function(){

      var onboardingOverlay =
        document.getElementById(
          "onboardingOverlay"
        );

      if(onboardingOverlay){
        onboardingOverlay.classList.remove(
          "show"
        );
      }

      localStorage.setItem(
        "platesOnboardingSeen",
        "true"
      );

    };

}

  
  var plateStateSelect = document.getElementById("plateStateSelect");

if (plateStateSelect) {
  plateStateSelect.addEventListener("change", function() {
    plateState = this.value;
    renderVanityPlate();
  });
}

var account = safeParse(
  localStorage.getItem("platesAccount"),
  '{"username":"","email":"","signedIn":false,"friendCode":""}'
);

  var plateState = localStorage.getItem("platesPlateState") || "NY";
  var mode = localStorage.platesMode || "classic";
var gameType = localStorage.platesGameType || (mode === "weighted" ? "battle" : mode === "unlimited" ? "roadtrip" : "solo");
var scoringMode = localStorage.platesScoringMode || mode || "classic";
mode = scoringMode;
var view = localStorage.platesView || "game";
var counts = safeParse(localStorage.platesCounts, "{}");
var log = safeParse(localStorage.platesLog, "[]");
var tripName = localStorage.platesTripName || "Summer Roadtrip";
var tripId =
  localStorage.platesTripId ||
  createTripId();

var tripStartedAt =
  localStorage.platesTripStartedAt ||
  new Date().toISOString();

var tripUpdatedAt =
  localStorage.platesTripUpdatedAt ||
  tripStartedAt;

var tripStatus =
  localStorage.platesTripStatus ||
  "active";
  
  var tripInviteCode = localStorage.platesInviteCode || "";
if (tripInviteCode.startsWith("ROAD-")) {
  tripInviteCode = tripInviteCode.replace("ROAD-", "PLT-");
  localStorage.platesInviteCode = tripInviteCode;
}

  var hasShownCompletion = localStorage.platesCompletionShown === "true";
var tripCount = Number(localStorage.platesTripCount || 1);
var savedTrips = safeParse(localStorage.platesSavedTrips, "[]");
var tripMemories = safeParse(localStorage.platesTripMemories, "[]");
var bestClassic = Number(localStorage.platesBestClassic || localStorage.platesBestTrip || 0);
var bestWeighted = Number(localStorage.platesBestWeighted || 0);
var bestUnlimited = Number(localStorage.platesBestUnlimited || 0);
var selectedState = "";
var collections =
  safeParse(
    localStorage.platesCollections,
    '{"states":[],"provinces":[],"plates":0}'
  );

  if(
  !localStorage.getItem(
    "platesCollectionsBackfilled"
  )
){

  Object.keys(counts).forEach(function(code){

    if(!counts[code]) return;

    var btn =
      document.querySelector(
        '[data-code="' + code + '"]'
      );

    if(
      btn &&
      btn.dataset.canada === "true"
    ){

      if(
        !collections.provinces.includes(code)
      ){
        collections.provinces.push(code);
      }

    } else {

      if(
        !collections.states.includes(code)
      ){
        collections.states.push(code);
      }

    }

  });

  collections.plates =
    Math.max(
      collections.plates || 0,
      totalSightings()
    );

  localStorage.platesCollections =
    JSON.stringify(collections);

  localStorage.setItem(
    "platesCollectionsBackfilled",
    "true"
  );
}
  var dailyChallenge;

try {

  dailyChallenge =
    JSON.parse(
      localStorage.dailyChallenge ||
      "null"
    );

} catch(e) {

  dailyChallenge = null;

}


var plateName = localStorage.getItem("platesPlateName") || "DCHIUNGOS";

function generateFriendCode(){
  return "PLT-" + Math.random().toString(36).substring(2, 8).toUpperCase();
}

function saveAccount(){
  localStorage.setItem("platesAccount", JSON.stringify(account));
}

function isSignedIn(){
  return account && account.signedIn && account.username;
}


function createAccount(){
  var overlay = document.getElementById("accountOverlay");
  var usernameInput = document.getElementById("accountUsernameInput");
  var emailInput = document.getElementById("accountEmailInput");

  

var stateInput =
  document.getElementById("accountStateInput");
  
  var title = document.querySelector("#accountOverlay .newGameTitle");
  var saveBtn = document.getElementById("accountSaveBtn");

  if(usernameInput) usernameInput.value = account.username || "";
  if(emailInput) emailInput.value = account.email || "";
if(stateInput){
  stateInput.value =
    account.state ||
    plateState ||
    "NY";
}
  if(title){
    title.textContent = isSignedIn() ? "✏️ Edit Account" : "👤 Create Account";
  }

  if(saveBtn){
    saveBtn.textContent = isSignedIn() ? "💾 Save Account" : "👤 Create Account";
  }


var accountAvatarPicker =
  document.querySelector("#accountOverlay .avatarPicker");

if(accountAvatarPicker){
  accountAvatarPicker.classList.remove("readOnly");
}
  
  if(overlay) overlay.classList.remove("hidden");
}

 function generateDailyChallenge(){

  var today =
    new Date().toDateString();

  if(
    dailyChallenge &&
    dailyChallenge.date === today
  ){
    return;
  }

  var allStates =
    Array.from(
      document.querySelectorAll(
        '.state:not([data-bonus="true"])'
      )
    );

  var missing =
    allStates.filter(function(btn){
      return !counts[btn.dataset.code];
    });

  var target =
    missing.length
      ? missing[
          Math.floor(
            Math.random() * missing.length
          )
        ]
      : states[
          Math.floor(
            Math.random() * states.length
          )
        ];

  var stateCode =
    target.dataset
      ? target.dataset.code
      : target.code;

  dailyChallenge = {
    date: today,
    type: "findState",
    state: stateCode,
    complete: false
  };

  localStorage.dailyChallenge =
    JSON.stringify(dailyChallenge);
}

  
function closeAccountSheet(){
  var overlay = document.getElementById("accountOverlay");
  if(overlay) overlay.classList.add("hidden");
}

function saveAccountFromSheet(){
  var usernameInput =
    document.getElementById(
      "accountUsernameInput"
    );

  var emailInput =
    document.getElementById(
      "accountEmailInput"
    );

  var stateInput =
    document.getElementById(
      "accountStateInput"
    );

  var username =
    usernameInput
      ? usernameInput.value
          .trim()
          .replace(/^@/, "")
      : "";

  var email =
    emailInput
      ? emailInput.value.trim()
      : "";

  var homeState =
    stateInput
      ? stateInput.value
      : "NY";
  
  if(!username) {
    toast("Username required");
    return;
  }

  if(!email) {
    toast("Email required");
    return;
  }



  
account = {
  username: username,
  email: email,
  state: homeState,
  signedIn: true,
  friendCode:
    account.friendCode ||
    generateFriendCode()
};

  
console.log(account);
saveAccount();

plateName = cleanPlateName(username);

plateState = homeState;

localStorage.setItem(
  "platesPlateState",
  plateState
);
  
localStorage.setItem(
  "platesPlateName",
  plateName
);

profile.plate = plateName;

profile.name = username;
profile.email = email;
localStorage.setItem("platesProfile", JSON.stringify(profile));

  
var cp = currentPlayer();

if(cp){
  cp.name = username;
  cp.plate = plateName;
  cp.avatar = profile.avatar || cp.avatar;
}

localStorage.platesPlayers =
  JSON.stringify(players);

renderVanityPlate();
loadProfile();


closeAccountSheet();
toast("Account saved");
render();


}

  function getDebateVoteKey(){

  var today =
    new Date()
      .toISOString()
      .slice(0,10);

  return "todayDebateVote-" + today;

}

var pendingDebateVote = "";

var debateVotes = {
  "ASSMAN": 38,
  "OUTATIME": 27,
  "ECTO-1": 35
};


function renderDebate(){

  var submittedVote =
localStorage.getItem(
  getDebateVoteKey()
)
    
  var submitBtn =
    document.getElementById("debateSubmitBtn");

  var votes = {
    "ASSMAN": debateVotes["ASSMAN"],
    "OUTATIME": debateVotes["OUTATIME"],
    "ECTO-1": debateVotes["ECTO-1"]
  };

  if(
    submittedVote &&
    votes[submittedVote] !== undefined
  ){
    votes[submittedVote] += 1;
  }

  var total =
    votes["ASSMAN"] +
    votes["OUTATIME"] +
    votes["ECTO-1"];

  document
    .querySelectorAll(".debateBtn")
    .forEach(function(btn){

      var vote = btn.dataset.vote;

      var label =
        btn.querySelector(".debateLabel");

      var percentEl =
        btn.querySelector(".debatePercent");

      var fill =
        btn.querySelector(".debateFill");

      var percent =
        Math.round(
          (votes[vote] / total) * 100
        );

      btn.classList.toggle(
        "selected",
        submittedVote
          ? vote === submittedVote
          : vote === pendingDebateVote
      );

      if(submittedVote){

        btn.disabled = true;

        if(percentEl){
          percentEl.textContent =
            percent + "%";
        }

        if(fill){
          fill.style.width =
            percent + "%";
        }

      } else {

        btn.disabled = false;

        if(percentEl){
          percentEl.textContent = "";
        }

        if(fill){
          fill.style.width = "0%";
        }
      }

      if(label){
        label.textContent = vote;
      }
    });

  if(submitBtn){

    if(submittedVote){
      submitBtn.textContent = "Vote Submitted";
      submitBtn.disabled = true;
      submitBtn.classList.add("submitted");
    } else {
      submitBtn.textContent = "Submit Vote";
      submitBtn.disabled = !pendingDebateVote;
      submitBtn.classList.remove("submitted");
    }
  }
}


  document
  .querySelectorAll(".debateBtn")
  .forEach(function(btn){

    btn.onclick = function(){

      if(
        localStorage.getItem(
          getDebateVoteKey()
        )
      ){
        return;
      }

      pendingDebateVote =
        btn.dataset.vote;

      renderDebate();
    };
  });


var debateSubmitBtn =
  document.getElementById(
    "debateSubmitBtn"
  );

if(debateSubmitBtn){

  debateSubmitBtn.onclick =
    function(){

      if(
        !pendingDebateVote
      ){
        return;
      }

      localStorage.setItem(
        getDebateVoteKey(),
        pendingDebateVote
      );

      pendingDebateVote =
        "";

      renderDebate();

    };

}


  

function stateNameFromCode(code) {
  var select =
    document.getElementById("accountStateInput");

  if(!select) return code || "NY";

  var option =
    select.querySelector(
      'option[value="' + code + '"]'
    );

  return option
  ? option.textContent
  : (code || "NY");
  
}


  function cleanPlateName(value) {
  return String(value || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 10);
}

  function getStateName(code){
  var btn = document.querySelector('.state[data-code="' + code + '"]');
  return btn ? btn.dataset.name : code;
}

function renderDailyChallenge(){

var found =
  dailyChallenge.complete ||
  log.some(function(x){
    return x.code === dailyChallenge.state;
  });

  if(!dailyChallenge) return;

  var title =
    document.getElementById("dailyChallengeTitle");

  var progress =
    document.getElementById("dailyChallengeProgress");

  var fill =
    document.getElementById("dailyChallengeFill");

  if(!title || !progress || !fill) return;

var found =
  dailyChallenge.complete ||
  log.some(function(x){
    return x.code === dailyChallenge.state;
  });

  title.textContent =
 "Find a " + getStateName(dailyChallenge.state) + " plate";

  progress.textContent =
    (found ? "1" : "0") + " / 1 Complete";

  fill.style.width =
    found ? "100%" : "0%";
}


function renderVanityPlate() {
  var input = document.getElementById("");
  var preview = document.getElementById("plateTextPreview");

  var stateSelect = document.getElementById("plateStateSelect");
  var statePreview = document.querySelector(".profilePlateHero .plateState");

  if (input) input.value = plateName;

  if (stateSelect) stateSelect.value = plateState;
  if (statePreview) statePreview.textContent = stateNameFromCode(plateState);

  if (preview) {
    preview.textContent = plateName || "PLATES";

    if (plateName.length >= 9) {
      preview.style.fontSize = "30px";
    } else if (plateName.length >= 8) {
      preview.style.fontSize = "33px";
    } else {
      preview.style.fontSize = "36px";
    }
  }
}
var plateInput = document.getElementById("");
if (plateInput) {
  plateInput.addEventListener("input", function() {
    plateName = cleanPlateName(this.value);
    this.value = plateName;
    renderVanityPlate();
  });
}

var savePlateBtn = document.getElementById("savePlateNameBtn");
if (savePlateBtn) {
  savePlateBtn.onclick = function() {
    plateName = cleanPlateName(document.getElementById("").value);
    localStorage.setItem("platesPlateName", plateName);
    renderVanityPlate();
    save();
  };
}

renderVanityPlate();


  var profile = safeParse(
  localStorage.getItem("platesProfile"),
  '{"name":"","email":"","avatar":"🚗"}'
);

  profile.avatar = profile.avatar || "🚗";





var players;

try {
  players = JSON.parse(
    localStorage.platesPlayers ||
    '[{"id":"p1","name":"Dean","avatar":"🚗"}]'
  );
} catch(e) {
  players = [];
}

if (!Array.isArray(players)) {
  players = [];
}

players = players.filter(function(p){
  return p && p.id && p.name;
});

if (!players.length) {
  players = [{
    id:"p1",
    name: profile.name || "Player",
    avatar: profile.avatar || "🚗"
  }];
}

players[0].name = profile.name || players[0].name || "Player";
players[0].avatar = profile.avatar || players[0].avatar || "🚗";

var currentPlayerId =
  localStorage.platesCurrentPlayerId ||
  (players[0] && players[0].id) ||
  "p1";

if (!players.some(function(p){
  return p.id === currentPlayerId;
})) {
  currentPlayerId = players[0].id;
}

var friends;

try {
  friends = JSON.parse(
    localStorage.getItem("friends") || "[]"
  );
} catch(e) {
  friends = [];
}

if (!Array.isArray(friends)) {
  friends = [];
}


function saveFriends() {
  localStorage.setItem(
    "friends",
    JSON.stringify(friends)
  );
}

var playerXP =
  parseInt(
    localStorage.getItem("playerXP")
  ) || 0;

function saveXP() {
  localStorage.setItem(
    "playerXP",
    playerXP
  );
}



function addXP(amount) {

  var oldLevel =
    getPlayerLevel();

  playerXP += amount;

  saveXP();

  var newLevel =
    getPlayerLevel();

  if(newLevel > oldLevel){


toast(
  "🎉 Level " +
  newLevel +
  " reached!"
);
    
  }

}

function getPlayerLevel(){

  return Math.floor(
    playerXP / 100
  ) + 1;

}
  
  var pendingPhotoStateCode = "";

  var hasSeenOnboarding = localStorage.platesSeenOnboarding === "true";


function renderFriends(){

  var friendsList =
    document.getElementById("friendsList");

  var friendsEmpty =
    document.getElementById("friendsEmpty");

  if(!friendsList){
    return;
  }

  friendsList.innerHTML = "";

  if(!friends.length){

    if(friendsEmpty){
      friendsEmpty.classList.remove("hidden");
    }

    return;
  }

  if(friendsEmpty){
    friendsEmpty.classList.add("hidden");
  }

  friends.forEach(function(friend){

    var row = document.createElement("div");
    row.className = "familyMember";

row.innerHTML =
  '<div class="familyAvatar">' +
    friend.avatar +
  '</div>' +

  '<div class="familyInfo">' +

    '<div class="familyName">' +
      friend.name +
    '</div>' +

    '<div class="familyMeta">' +
      friend.id +
    '</div>' +

    '<div class="familyStats">' +
      friend.stateCount + ' states • ' +
      friend.points + ' pts' +
    '</div>' +

  '</div>' +

  '<button class="removeFriendBtn" type="button">' +
    '✕' +
  '</button>';


    var removeFriendBtn =
  row.querySelector(".removeFriendBtn");

removeFriendBtn.onclick = function(){

  friends = friends.filter(function(savedFriend){
    return savedFriend.id !== friend.id;
  });

  saveFriends();
  renderFriends();
  renderFriendLeaderboard();
  toast("Friend removed");

};

    
    friendsList.appendChild(row);

  });

}
  

function renderFriendLeaderboard(){

  var box =
    document.getElementById(
      "friendLeaderboard"
    );

  if(!box){
    return;
  }

  box.innerHTML = "";

  var players = [];

  players.push({
    name:
      document.getElementById(
        "plateTextPreview"
      )?.textContent.trim() || "You",

    points:
      typeof totalScore === "function"
        ? totalScore()
        : 0
  });

  friends.forEach(function(friend){

    players.push({
      name: friend.name,
      points: friend.points || 0
    });

  });

  players.sort(function(a,b){
    return b.points - a.points;
  });

  players.forEach(function(player,index){

    var row =
      document.createElement("div");

    row.className =
      "leaderboardRow";

    row.innerHTML =
      '<div>#' +
        (index+1) +
        ' ' +
        player.name +
      '</div>' +

      '<div>' +
        player.points +
        ' pts' +
      '</div>';

    box.appendChild(row);

  });

}
  

  
  
  
  function showOnboardingIfNeeded() {
  if(!hasSeenOnboarding) {
    var overlay = document.getElementById("onboardingOverlay");
    if(overlay) overlay.classList.add("show");
  }
}
function getTripInviteCode() {
  if(!tripInviteCode) {
    tripInviteCode = "PLT-" + Math.floor(1000 + Math.random() * 9000);
    localStorage.platesInviteCode = tripInviteCode;
  }
  return tripInviteCode;
}
function dismissOnboarding() {
  hasSeenOnboarding = true;
  localStorage.platesSeenOnboarding = "true";
  var overlay = document.getElementById("onboardingOverlay");
  if(overlay) overlay.classList.remove("show");
}



function loadProfile() {
  var nameInput = document.getElementById("profileName");
  var emailInput = document.getElementById("profileEmail");
var plateInput = document.getElementById("plateNameInput");

  if(nameInput) nameInput.value = profile.name || "";
  if(emailInput) emailInput.value = profile.email || "";

  if(plateInput) {
    plateInput.value = plateName || profile.name || "";
  }

  renderVanityPlate();

  var preview = document.getElementById("avatarPreview");
  if(preview) preview.textContent = profile.avatar || "🚗";

  document.querySelectorAll(".avatarBtn").forEach(function(btn){
    if(btn.dataset.avatar === profile.avatar) {
      btn.classList.add("selected");
    } else {
      btn.classList.remove("selected");
    }
  });


  var plateDisplay = document.getElementById("profilePlateDisplay");
if(plateDisplay) plateDisplay.textContent = plateName || account.username || "PLATES";

var stateDisplay = document.getElementById("profileStateDisplay");
if(stateDisplay) stateDisplay.textContent = stateNameFromCode(plateState);

  var friendCodeDisplay = document.getElementById("friendCodeDisplay");
if(friendCodeDisplay) {
  friendCodeDisplay.textContent = account.friendCode || "";
}


var profileAvatarPicker =
  document.querySelector("#profileScreen .avatarPicker");

if(profileAvatarPicker){
  profileAvatarPicker.classList.add("readOnly");
}

}



function saveProfile() {
  var nameInput = document.getElementById("profileName");
  var emailInput = document.getElementById("profileEmail");

  profile.name = nameInput ? nameInput.value.trim() : "";
  profile.email = emailInput ? emailInput.value.trim() : "";


  console.log("Saved profile:", profile);
var cp = currentPlayer();

if (cp) {
  cp.name = profile.name || "Player";
  cp.avatar = profile.avatar || "🚗";
  cp.plate = plateName;
  cp.plateState = plateState;
}

localStorage.platesPlayers = JSON.stringify(players);

var saveBtn = document.getElementById("saveProfileBtn");



var saveBtn = document.getElementById("saveProfileBtn");

if(saveBtn) {
  saveBtn.textContent = "Saved ✓";

  setTimeout(function() {
    saveBtn.textContent = "Save Profile";
  }, 2000);
}

var plateInput = document.getElementById("");
if (plateInput) {
  plateName = cleanPlateName(plateInput.value);
}

var stateSelect = document.getElementById("plateStateSelect");
if (stateSelect) {
  plateState = stateSelect.value;
}

profile.plate = plateName;
profile.plateState = plateState;



var cp = currentPlayer();
if(cp){
  cp.name = username;
  cp.plate = plateName;
  cp.plateState = plateState;
  cp.avatar = profile.avatar || cp.avatar;
}

localStorage.setItem("platesProfile", JSON.stringify(profile));
localStorage.platesPlayers = JSON.stringify(players);

renderVanityPlate();
render();

toast("Profile saved");
 }

function createTripId() {
  return (
    "trip-" +
    Date.now() +
    "-" +
    Math.random()
      .toString(36)
      .slice(2, 8)
  );
}

function formatTripDate(iso) {
  if(!iso) return "";

  var date = new Date(iso);

  if(isNaN(date.getTime())) {
    return "";
  }

  return (
    (date.getMonth() + 1) +
    "/" +
    date.getDate() +
    "/" +
    String(date.getFullYear()).slice(-2)
  );
}

  

function formatTripDateRange(startIso, endIso) {
  var start = formatTripDate(startIso);
  var end = formatTripDate(endIso);

  if(!start) return "";
  if(!end || start === end) return start;

  return start + " – " + end;
}

function beginFreshTrip(name) {
  tripId = createTripId();
  tripName = name || "New Roadtrip";
  tripStartedAt = new Date().toISOString();
  tripUpdatedAt = tripStartedAt;
  tripStatus = "active";

  counts = {};
  log = [];
tripMemories = [];
  
  localStorage.removeItem(
    "platesPausedTrip"
  );
}

function activeTripData() {
  return {
    id: tripId,
    name: tripName,
    gameType: gameType,
    mode: mode,
    scoringMode: scoringMode,
    counts: counts,
    log: log,
    memories: tripMemories || [],
    startedAt: tripStartedAt,
    updatedAt: tripUpdatedAt,
    status: tripStatus
  };
}
  
function save() {
  localStorage.platesMode = mode;
  localStorage.platesGameType = gameType;
  localStorage.platesScoringMode = scoringMode;
  localStorage.platesView = view;
  localStorage.platesCounts = JSON.stringify(counts);
  localStorage.platesLog = JSON.stringify(log);
  localStorage.platesTripName = tripName;

tripUpdatedAt = new Date().toISOString();

localStorage.platesTripId =
  tripId;

localStorage.platesTripStartedAt =
  tripStartedAt;

localStorage.platesTripUpdatedAt =
  tripUpdatedAt;

localStorage.platesTripStatus =
  tripStatus;
  
  localStorage.platesTripCount = tripCount;
  localStorage.platesSavedTrips = JSON.stringify(savedTrips);
  localStorage.platesTripMemories = JSON.stringify(tripMemories);
  localStorage.platesCollections = JSON.stringify(collections);
  localStorage.platesBestClassic = bestClassic;
  localStorage.platesBestWeighted = bestWeighted;
  localStorage.platesBestUnlimited = bestUnlimited;
localStorage.platesPlayers = JSON.stringify(players);
localStorage.platesCurrentPlayerId = currentPlayerId;
  localStorage.platesPlateName = plateName;
localStorage.platesPlateState = plateState;
}

function bonusCollectedCount() {
  var total = 0;
  document
    .querySelectorAll('.state[data-bonus="true"]')
    .forEach(function(btn){
      if(counts[btn.dataset.code]) {
        total++;
      }
    });
  return total;
}


function bonusCollectedCount() {
  var total = 0;
  document.querySelectorAll('.state[data-bonus="true"]').forEach(function(btn){
    if(counts[btn.dataset.code]) {
      total++;
    }
  });
  return total;
}

function canadaCollectedCount(){

  var total = 0;

  document
    .querySelectorAll(
      '.state[data-canada="true"]'
    )
    .forEach(function(btn){

      if(counts[btn.dataset.code]){
        total++;
      }
    });

  return total;
}
  

function collectedCount() {
  var unique = {};

  if (Array.isArray(log)) {
    log.forEach(function(item){
      if (!item || !item.code) return;

      var stateBtn = document.querySelector(
        '.state[data-code="' + item.code + '"]'
      );

      if (stateBtn && stateBtn.dataset.bonus === "true") return;

      unique[item.code] = true;
    });
  }

  return Object.keys(unique).length;
}


  function totalScore() {
  var total = 0;

  document.querySelectorAll(".state").forEach(function(btn){
    var code = btn.dataset.code;
    var points = Number(btn.dataset.points);
    var isBonus = btn.dataset.bonus === "true";

    if (mode === "classic") {
      if (!isBonus && counts[code]) {
        total += 1;
      }
    }

    if (mode === "weighted") {
      if (counts[code]) {
        total += points;
      }
    }

    if (mode === "unlimited") {
      total += (counts[code] || 0) * points;
    }
  });

  return total;
}

function totalSightings() {
  return Array.isArray(log) ? log.length : 0;
}

function updateBestForCurrentMode() {
  var c = collectedCount();
  var points = totalScore();
  if(mode === "classic" && c > bestClassic) bestClassic = c;
  if(mode === "weighted" && points > bestWeighted) bestWeighted = points;
  if(mode === "unlimited" && points > bestUnlimited) bestUnlimited = points;
}

function bestForCurrentMode() {
  if(mode === "classic") return bestClassic;
  if(mode === "weighted") return bestWeighted;
  if(mode === "unlimited") return bestUnlimited;
  return bestClassic;
}


function toast(text) {
  var el = document.getElementById("toast");
  el.textContent = text;
  el.classList.add("show");
  clearTimeout(window.toastTimer);
  window.toastTimer = setTimeout(function(){ el.classList.remove("show"); }, 1300);
}

function showCelebration(
  title,
  text,
  icon
){

  document.getElementById(
    "celebrationTitle"
  ).textContent = title;

  document.getElementById(
    "celebrationText"
  ).textContent = text;

  document.getElementById(
    "celebrationIcon"
  ).textContent = icon || "🏅";

  document.getElementById(
    "celebrationOverlay"
  ).classList.add("show");
}

  
  
function badgeCount(c) {
  var total = 0;
  if(c >= 1) total++;
  if(c >= 10) total++;
  if(c >= 25) total++;
  if(c >= 50) total++;
  if(hasStates(["AK","HI"])) total++;
  if(hasStates(["CA","OR","WA"])) total++;
  if(rareCollectedCount() >= 5) total++;
  if(totalSightings() >= 100) total++;
  return total;
}

function hasStates(list) {
  return list.every(function(c){ return counts[c] > 0; });
}

function rareCollectedCount() {
  var total = 0;
  document.querySelectorAll(".state").forEach(function(btn){
    if(counts[btn.dataset.code] && Number(btn.dataset.points) >= 8) total++;
  });
  return total;
}



function tapState(btn) {
  var code = btn.dataset.code;
  var name = btn.dataset.name;
  var points = Number(btn.dataset.points);
  var wasCollected = !!counts[code];
  var before = collectedCount();

  if(mode === "classic" || mode === "weighted") {
    if(counts[code]) {
      counts[code] = 0;
      log = log.filter(function(item){ return item.code !== code; });
    } else {
      counts[code] = 1;
    }
  } else {
    counts[code] = (counts[code] || 0) + 1;

    
  }

  if(counts[code] && (!wasCollected || mode === "unlimited")) {
collections.plates++;

if(
  btn.dataset.canada === "true"
){

  if(
    !collections.provinces.includes(code)
  ){
    collections.provinces.push(code);
  }

} else {

  if(
    !collections.states.includes(code)
  ){
    collections.states.push(code);
  }

}
    
    log.unshift({
      code:code,
      name:name,
      points:points,
      mode:mode,
      trip:tripName,
      playerId:currentPlayerId,
      playerName:currentPlayer().name,
      ts:new Date().toISOString()
    });
    log = log.slice(0, 30);

addActivity(
  "👀 Found " + name
);
    
    btn.classList.add("celebrate");
    setTimeout(function(){ btn.classList.remove("celebrate"); }, 600);


if(!wasCollected) {

  var xpEarned = 10;

  var completedDailyChallenge =
    dailyChallenge &&
    dailyChallenge.state === code &&
    !dailyChallenge.complete;

  if(completedDailyChallenge){

    xpEarned += 250;

    dailyChallenge.complete = true;

    localStorage.dailyChallenge =
      JSON.stringify(
        dailyChallenge
      );
  }

  addXP(xpEarned);

  if(completedDailyChallenge){

    toast(
      "Daily Challenge Complete" +
      "\n+" +
      xpEarned +
      " XP"
    );

  } else {

    toast(
      "Collected " +
      name +
      "\n+10 XP"
    );

  }
    

  var isBonus =
    btn.dataset.bonus === "true";

  if(!isBonus){

    var after =
      collectedCount();

    if(after === 1){
      showCelebration(
        "First Plate",
        "You started your collection with " + name,
        "🧢"
      );
    }

    else if(after === 10){
      showCelebration(
        "10 States",
        "You've found 10 states on this trip",
        "🧭"
      );
    }

    else if(after === 25){
      showCelebration(
        "Halfway There",
        "25 states collected",
        "🧩"
      );
    }

     else if(after === 50){
      showCelebration(
        "All 50 States",
        "You completed the game",
        "🏆"
      );
    }
  }
}
}

updateBestForCurrentMode();
save();
render();
}
function gameTypeLabel() {
  return gameType === "battle" ? "Battle" :
    gameType === "roadtrip" ? "Roadtrip" :
    "Solo";
}

function scoringModeLabel() {
  return mode === "weighted" ? "Weighted" :
    mode === "unlimited" ? "Unlimited" :
    "Classic";
}

function gameSummaryLabel() {
  return gameTypeLabel() + " • " + scoringModeLabel();
}

function syncNewGameSheet() {
  document.querySelectorAll("[data-game-type]").forEach(function(btn){
    btn.classList.toggle("active", btn.dataset.gameType === gameType);
  });

  document.querySelectorAll("[data-mode-choice]").forEach(function(btn){
    btn.classList.toggle("active", btn.dataset.modeChoice === mode);
  });
}


function openNewGameSheet(){

  var input =
    document.getElementById(
      "newGameNameInput"
    );

  var overlay =
    document.getElementById(
      "newGameOverlay"
    );

  var nameSection =
    document.getElementById(
      "newGameNameSection"
    );

  var typeSection =
    document.getElementById(
      "newGameTypeSection"
    );

  var createBtn =
    document.getElementById(
      "createGameBtn"
    );

  var title =
    overlay
      ? overlay.querySelector(
          ".newGameTitle"
        )
      : null;

  if(
    overlay &&
    overlay.dataset.mode === "change"
  ){

    if(createBtn){
      createBtn.textContent =
        "✅ Save Scoring";
    }

    if(nameSection){
      nameSection.classList.add(
        "hidden"
      );
    }

    if(typeSection){
      typeSection.classList.add(
        "hidden"
      );
    }

    if(title){
      title.textContent =
        "⚙️ Change Scoring";
    }

  } else {

    if(input){
      input.value = "";
      input.placeholder =
        "Summer Road Trip";
    }

    if(createBtn){
      createBtn.textContent =
        "🚗 Start New Trip";
    }

    if(nameSection){
      nameSection.classList.remove(
        "hidden"
      );
    }

    if(typeSection){
      typeSection.classList.remove(
        "hidden"
      );
    }

    if(title){
      title.textContent =
        "🚗 New Game";
    }
  }

  syncNewGameSheet();

  if(overlay){
    overlay.classList.remove(
      "hidden"
    );
  }
}
  
function closeNewGameSheet(){

  var overlay =
    document.getElementById(
      "newGameOverlay"
    );

  if(overlay){

    overlay.classList.add(
      "hidden"
    );

    overlay.dataset.mode = "";

  }
}

function createGameFromSheet() {

  var overlay =
    document.getElementById(
      "newGameOverlay"
    );

  if(
    overlay &&
    overlay.dataset.mode === "change"
  ){

    scoringMode =
      mode || "classic";

    overlay.dataset.mode = "";

    save();
    render();
    closeNewGameSheet();

    toast("Trip scoring updated");
    return;
  }

  var input =
    document.getElementById(
      "newGameNameInput"
    );

  var name =
    input
      ? input.value.trim()
      : "";

  if(!name){
    toast(
      "Please enter a trip name"
    );
    return;
  }

  tripName = name;

  scoringMode =
    mode ||
    scoringMode ||
    "classic";

  counts = {};
  log = [];

  addActivity(
    "🛣️ Started " + tripName
  );

  save();
  render();
  closeNewGameSheet();

  toast("New trip started");
}
  

function setMode(newMode) {
  mode = newMode;
  scoringMode = newMode;


  updateBestForCurrentMode();
  save();
  render();
}

function setView(newView) {
  view = newView;
  save();
  render();
  window.scrollTo(0,0);
}



function openClearTripSheet(){

  var optionsOverlay =
    document.getElementById(
      "gameOptionsOverlay"
    );

  if(optionsOverlay){
    optionsOverlay.classList.add(
      "hidden"
    );
  }

  var clearOverlay =
    document.getElementById(
      "clearTripOverlay"
    );

  if(clearOverlay){
    clearOverlay.classList.remove(
      "hidden"
    );
  }
}


function closeClearTripSheet(){

  var clearOverlay =
    document.getElementById(
      "clearTripOverlay"
    );

  if(clearOverlay){
    clearOverlay.classList.add(
      "hidden"
    );
  }
}


function clearTrip(){

  counts = {};
  log = [];
  score = 0;

  save();
  render();

  closeClearTripSheet();

  toast("Trip cleared");
}



  

function renameTrip(){
  openTripNameSheet();
}

function currentTripSnapshot() {
  var endedAt =
    new Date().toISOString();

  return {
    id: tripId,
    name: tripName,
    gameType: gameType,
    mode: mode,
    scoringMode: scoringMode,

    states: collectedCount(),
    score: totalScore(),
    sightings: totalSightings(),
    badges: badgeCount(
      collectedCount()
    ),

    counts: JSON.parse(
      JSON.stringify(counts)
    ),

    log: JSON.parse(
      JSON.stringify(log)
    ),


    memories: tripMemories
      .filter(function(m) {
        return m.trip === tripName;
      })
      .map(function(m) {
        return Object.assign({}, m);
      }),

    memoryCount: tripMemories.filter(
      function(m) {
        return m.trip === tripName;
      }
    ).length,

    startedAt: tripStartedAt,
    
    updatedAt: tripUpdatedAt,
    endedAt: endedAt,

    date: formatTripDateRange(
      tripStartedAt,
      endedAt
    ),

    status: "completed"
  };
}



  function openNextTripNameSheet(){

  var overlay =
    document.getElementById(
      "nextTripNameOverlay"
    );

  if(overlay){
    overlay.dataset.mode = "new";
  }

  var input =
    document.getElementById(
      "nextTripNameInput"
    );

  if(input){
    input.value = "";
  }

  if(overlay){
    overlay.classList.remove("hidden");
  }

  setTimeout(function(){
    if(input){
      input.focus();
    }
  },100);
}

  function closeNextTripNameSheet(){

  var overlay =
    document.getElementById(
      "nextTripNameOverlay"
    );

  if(overlay){
    overlay.classList.add(
      "hidden"
    );
  }
}

function openTripNameSheet(){

  var overlay =
    document.getElementById(
      "tripNameOverlay"
    );

  var input =
    document.getElementById(
      "tripNameInput"
    );

  if(input){
    input.value =
      tripName || "";
  }

  overlay.classList.remove(
    "hidden"
  );
}

function closeTripNameSheet(){

  document
    .getElementById(
      "tripNameOverlay"
    )
    .classList.add(
      "hidden"
    );
}

function saveNextTripName(){

  var overlay =
    document.getElementById(
      "nextTripNameOverlay"
    );

  var input =
    document.getElementById(
      "nextTripNameInput"
    );

  var nextName =
    input
      ? input.value.trim()
      : "";

  var isRename =
    overlay &&
    overlay.dataset.mode ===
      "rename";

  if(isRename){

    var oldName =
      tripName;

    tripName =
      nextName ||
      "New Roadtrip";

    tripMemories.forEach(
      function(m){

        if(m.trip === oldName){
          m.trip = tripName;
        }
      }
    );

    toast("Trip renamed");

  } else {

    beginFreshTrip(
      nextName ||
      "New Roadtrip"
    );

    toast("New trip started");
  }

  if(overlay){
    overlay.dataset.mode = "";
  }

  closeNextTripNameSheet();

  save();
  render();
}


function endCurrentTrip() {
  if(collectedCount() === 0) {

    var emptyOptionsOverlay =
      document.getElementById(
        "gameOptionsOverlay"
      );

    if(emptyOptionsOverlay){
      emptyOptionsOverlay.classList.add(
        "hidden"
      );
    }

    openNewGameSheet();
    return;
  }

  var completedTrip =
    currentTripSnapshot();

  var existingIndex =
    savedTrips.findIndex(
      function(t) {
        return t.id === completedTrip.id;
      }
    );

  if(existingIndex >= 0) {
    savedTrips[existingIndex] =
      completedTrip;
  } else {
    savedTrips.unshift(
      completedTrip
    );
  }

  savedTrips =
    savedTrips.slice(0, 50);

  updateBestForCurrentMode();

  tripCount += 1;

  save();

  var optionsOverlay =
    document.getElementById(
      "gameOptionsOverlay"
    );

  if(optionsOverlay){
    optionsOverlay.classList.add(
      "hidden"
    );
  }

  openNewGameSheet();

  toast("Trip saved");
}


function saveArchivedTripMemory(index, memory){

  var t =
    savedTrips[index];

  if(!t){
    toast("Trip not found");
    return false;
  }

  if(
    !Array.isArray(
      t.memories
    )
  ){
    t.memories = [];
  }

  t.memories.unshift(
    memory
  );

  t.memoryCount =
    t.memories.length;

  try{

    localStorage.setItem(
      "platesSavedTrips",
      JSON.stringify(
        savedTrips
      )
    );

  } catch(error){

    t.memories.shift();

    t.memoryCount =
      t.memories.length;

    console.error(
      "Memory save failed:",
      error
    );

    toast(
      "Photo is too large to save"
    );

    return false;
  }

  openTripDetails(index);

  toast("Memory saved");

  return true;
}


function addArchivedTripNote(index){

  var t =
    savedTrips[index];

  if(!t){
    toast("Trip not found");
    return;
  }

  var title =
    prompt(
      "Memory title:",
      "Trip memory"
    );

  if(
    !title ||
    !title.trim()
  ){
    return;
  }

  var note =
    prompt(
      "Add a note:",
      ""
    );

  if(note === null){
    return;
  }

  saveArchivedTripMemory(
    index,
    {
      id:
        "m" +
        Date.now() +
        Math.floor(
          Math.random() * 1000
        ),

      type: "note",

      tripId:
        t.id,

      trip:
        t.name,

      stateCode: "",
      stateName: "",

      title:
        title.trim(),

      note:
        (note || "").trim(),

      ts:
        new Date().toISOString()
    }
  );
}



function addArchivedTripPhoto(
  index,
  file
){

  var t =
    savedTrips[index];

  if(
    !t ||
    !file
  ){
    return;
  }

  var reader =
    new FileReader();

  reader.onload =
    function(event){

      var image =
        new Image();

      image.onload =
        function(){

          var maxSize = 650;

          var width =
            image.width;

          var height =
            image.height;

          if(
            width > height &&
            width > maxSize
          ){

            height =
              Math.round(
                height *
                maxSize /
                width
              );

            width =
              maxSize;
          }

          if(
            height >= width &&
            height > maxSize
          ){

            width =
              Math.round(
                width *
                maxSize /
                height
              );

            height =
              maxSize;
          }

          var canvas =
            document.createElement(
              "canvas"
            );

          canvas.width =
            width;

          canvas.height =
            height;

          var context =
            canvas.getContext(
              "2d"
            );

          context.drawImage(
            image,
            0,
            0,
            width,
            height
          );

          var photo =
            canvas.toDataURL(
              "image/jpeg",
              0.58
            );

          var overlay =
            document.getElementById(
              "memoryOverlay"
            );

          var preview =
            document.getElementById(
              "memoryPreview"
            );

          var noteInput =
            document.getElementById(
              "memoryCaptionInput"
            );

          var saveBtn =
            document.getElementById(
              "saveMemoryBtn"
            );

          var closeBtn =
            document.getElementById(
              "memoryCloseBtn"
            );

          var cancelBtn =
            document.getElementById(
              "cancelMemoryBtn"
            );

          if(
            !overlay ||
            !preview ||
            !noteInput ||
            !saveBtn
          ){

            toast(
              "Memory sheet could not open"
            );

            return;
          }

          preview.src =
            photo;

          preview.classList.remove(
            "hidden"
          );

          noteInput.value = "";

          overlay.classList.remove(
            "hidden"
          );

          setTimeout(
            function(){

              noteInput.focus();

            },
            150
          );


          function closeArchivedMemorySheet(){

            overlay.classList.add(
              "hidden"
            );

            preview.src = "";

            preview.classList.add(
              "hidden"
            );

            noteInput.value = "";
          }


          saveBtn.onclick =
            function(){

              var note =
                noteInput.value.trim();

              saveArchivedTripMemory(
                index,
                {
                  id:
                    "m" +
                    Date.now() +
                    Math.floor(
                      Math.random() *
                      1000
                    ),

                  type:
                    "photo",

                  tripId:
                    t.id,

                  trip:
                    t.name,

                  stateCode: "",
                  stateName: "",

                  title:
                    note ||
                    "Photo memory",

                  note:
                    note,

                  caption:
                    note,

                  photo:
                    photo,

                  ts:
                    new Date()
                      .toISOString()
                }
              );

              closeArchivedMemorySheet();
            };


          if(closeBtn){

            closeBtn.onclick =
              closeArchivedMemorySheet;
          }


          if(cancelBtn){

            cancelBtn.onclick =
              closeArchivedMemorySheet;
          }


          overlay.onclick =
            function(clickEvent){

              if(
                clickEvent.target ===
                overlay
              ){

                closeArchivedMemorySheet();
              }
            };
        };

      image.src =
        event.target.result;
    };

  reader.readAsDataURL(
    file
  );
}

  
function escapeMemoryText(value){

  return String(
    value || ""
  )
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}



  function renderArchivedTripMemories(index){

  var t =
    savedTrips[index];

  if(
    !t ||
    !Array.isArray(t.memories) ||
    !t.memories.length
  ){
    return "No memories saved yet";
  }

  return (
    '<div class="archivedMemoryList">' +

      t.memories
        .filter(function(memory){

          return (
            memory &&
            memory.photo
          );

        })
        .map(function(memory){

          var note =
            memory.note ||
            memory.caption ||
            "";

          return (
            '<button' +
              ' class="archivedMemoryItem"' +
              ' type="button"' +
              ' data-memory-id="' +
                escapeMemoryText(
                  memory.id
                ) +
              '">' +

              '<img' +
                ' class="archivedMemoryThumb"' +
                ' src="' +
                  memory.photo +
                '"' +
                ' alt="Trip memory">' +

              '<span class="archivedMemoryText">' +

                '<span class="archivedMemoryNote">' +
                  escapeMemoryText(
                    note ||
                    "Photo memory"
                  ) +
                '</span>' +

                '<span class="archivedMemoryDate">' +
                  formatShortDate(
                    memory.ts
                  ) +
                '</span>' +

              '</span>' +

            '</button>'
          );

        })
        .join("") +

    '</div>'
  );

}






function openTripDetails(index) {

  var t =
    savedTrips[index]

  if(!t){
    toast("Trip not found")
    return
  }

  var nameEl =
    document.getElementById(
      "tripDetailName"
    )

  var dateEl =
    document.getElementById(
      "tripDetailDate"
    )

  var modeEl =
    document.getElementById(
      "tripDetailMode"
    )

  var statesEl =
    document.getElementById(
      "tripDetailStates"
    )

  var sightingsEl =
    document.getElementById(
      "tripDetailSightings"
    )

  var pointsEl =
    document.getElementById(
      "tripDetailPoints"
    )

  var badgesEl =
    document.getElementById(
      "tripDetailBadges"
    )

  var memoriesEl =
    document.getElementById(
      "tripDetailMemories"
    )

  var resumeBtn =
    document.getElementById(
      "tripDetailResumeBtn"
    )

  var shareBtn =
    document.getElementById(
      "tripDetailShareBtn"
    )

  var deleteBtn =
    document.getElementById(
      "tripDetailDeleteBtn"
    )

  var backBtn =
    document.getElementById(
      "tripDetailBackBtn"
    )


  var addPhotoBtn =
  document.getElementById(
    "tripDetailAddPhotoBtn"
  )



  
var photoInput =
  document.getElementById(
    "tripDetailPhotoInput"
  )


  nameEl.textContent =
    t.name || "Roadtrip"

  dateEl.textContent =
    formatTripDateRange(
      t.startedAt,
      t.endedAt
    ) ||
    t.date ||
    "Date unavailable"

  modeEl.textContent =
    (
      t.mode
        ? t.mode.charAt(0).toUpperCase() +
          t.mode.slice(1)
        : "Classic"
    ) +
    " Mode"

  statesEl.textContent =
    Number(t.states) || 0

  sightingsEl.textContent =
    Number(t.sightings) || 0

  pointsEl.textContent =
    Number(t.score) || 0


  var badgeTotal =
    Number(t.badges) || 0

  badgesEl.textContent =
    badgeTotal +
    " badge" +
    (
      badgeTotal === 1
        ? ""
        : "s"
    )



  var memoryTotal =
  Array.isArray(t.memories)
    ? t.memories.length
    : 0

memoriesEl.innerHTML =
  renderArchivedTripMemories(
    index
  )

memoriesEl.onclick =
  function(event){

    var memoryItem =
      event.target.closest(
        ".archivedMemoryItem"
      )

    if(!memoryItem){
      return
    }

    openArchivedMemoryViewer(
      index,
      memoryItem.dataset.memoryId
    )
  }

  

  resumeBtn.onclick =
    function(){

      resumeSavedTrip(index)

    }

  shareBtn.onclick =
    function(){

      shareSavedTrip(index)

    }

  deleteBtn.onclick =
    function(){

      deleteSavedTrip(index)

    }



  

addPhotoBtn.onclick =
  function(){

    photoInput.value = ""

    photoInput.click()

  }


photoInput.onchange =
  function(){

    var file =
      photoInput.files &&
      photoInput.files[0]

    if(!file){
      return
    }

    addArchivedTripPhoto(
      index,
      file
    )

  }

  
  backBtn.onclick =
    function(){

      setView("trips")

    }


  document
    .querySelectorAll(".screen")
    .forEach(function(screen){

      screen.classList.add(
        "hidden"
      )

    })

  document
    .getElementById(
      "tripDetailScreen"
    )
    .classList.remove(
      "hidden"
    )

  window.scrollTo(0,0)

}


  

  
  
function shareSavedTrip(index) {
  var t = savedTrips[index];
  if(!t) return;

  var text =
    t.name + "\n\n" +
    t.date + "\n" +
    t.mode.charAt(0).toUpperCase() + t.mode.slice(1) + " Mode\n" +
    t.states + "/50 States\n\n" +
    "Playing Plates: The License Plate Game 🚗🇺🇸";

  if(navigator.share) {
    navigator.share({
      title: "My Plates Trip",
      text: text
    });
  } else {
    alert(text);
  }
}


function resumeSavedTrip(index, confirmed) {

  var t =
    savedTrips[index];

  if(!t) {

    toast(
      "Trip not found"
    );

    return;

  }

  var hasCurrentProgress =
    collectedCount() > 0 ||
    log.length > 0;

  var isDifferentTrip =
    tripId !== t.id;


  if(
    hasCurrentProgress &&
    isDifferentTrip &&
    !confirmed
  ){

    showConfirmSheet({

      icon:"▶",

      title:"Resume Trip",

      tripName:t.name,

      message:
        "Your current trip will be automatically archived",

      buttonText:
        "Resume Trip",

      onConfirm:function(){

        resumeSavedTrip(
          index,
          true
        );

      }

    });

    return;

  }


  if(
    hasCurrentProgress &&
    isDifferentTrip &&
    confirmed
  ){

    var currentSnapshot =
      currentTripSnapshot();

    var currentIndex =
      savedTrips.findIndex(
        function(savedTrip) {

          return (
            savedTrip.id ===
            currentSnapshot.id
          );

        }
      );

    if(currentIndex >= 0){

      savedTrips[currentIndex] =
        currentSnapshot;

    } else {

      savedTrips.unshift(
        currentSnapshot
      );

    }

  }


  savedTrips =
    savedTrips.filter(
      function(savedTrip) {

        return (
          savedTrip.id !==
          t.id
        );

      }
    );


  tripId =
    t.id ||
    createTripId();

  tripName =
    t.name ||
    "Roadtrip";

  gameType =
    t.gameType ||
    "solo";

  mode =
    t.mode ||
    "classic";

  scoringMode =
    t.scoringMode ||
    mode;


  counts =
    JSON.parse(
      JSON.stringify(
        t.counts || {}
      )
    );

  log =
    JSON.parse(
      JSON.stringify(
        t.log || []
      )
    );


  if(
    Array.isArray(
      t.memories
    )
  ){

    t.memories.forEach(
      function(memory){

        var alreadyExists =
          tripMemories.some(
            function(existingMemory){

              return (
                existingMemory.id &&
                memory.id &&
                existingMemory.id ===
                  memory.id
              );

            }
          );

        if(!alreadyExists){

          tripMemories.push(
            JSON.parse(
              JSON.stringify(
                memory
              )
            )
          );

        }

      }
    );

  }


  tripStartedAt =
    t.startedAt ||
    new Date().toISOString();

  tripUpdatedAt =
    new Date().toISOString();

  tripStatus =
    "active";


  localStorage.removeItem(
    "platesPausedTrip"
  );


view = "game";

try {

  save();

} catch(err) {

  console.error(
    "Resume Trip failed:",
    err
  );

  toast(
    "Trip could not be resumed"
  );

  return;

}

render();

toast(
  tripName +
  " resumed"
);

  }
  
  function newTrip() {

  var hasProgress =
    collectedCount() > 0 ||
    log.length > 0;

  if(
    hasProgress &&
    !confirm(
      "Start a new trip? Your current progress will be saved so you can resume it later"
    )
  ) {
    return;
  }


  
  if(hasProgress) {
    localStorage.setItem(
      "platesPausedTrip",
      JSON.stringify(
        activeTripData()
      )
    );
  }

  updateBestForCurrentMode();

  tripCount += 1;

  var nextName =
    prompt(
      "Trip name:",
      "New Roadtrip"
    ) || "New Roadtrip";


    
  beginFreshTrip(nextName);

  save();
  render();

  toast(
    hasProgress
      ? "Trip saved for later"
      : "New trip started"
  );
}


function getPausedTrip() {
  return safeParse(
    localStorage.getItem(
      "platesPausedTrip"
    ),
    "null"
  );
}


function resumePausedTrip() {
  var paused =
    getPausedTrip();

  if(!paused) {
    toast("No saved trip to resume");
    return;
  }

  tripId =
    paused.id ||
    createTripId();

  tripName =
    paused.name ||
    "Roadtrip";

  gameType =
    paused.gameType ||
    "solo";

  mode =
    paused.mode ||
    "classic";

  scoringMode =
    paused.scoringMode ||
    mode;

  counts =
    paused.counts || {};

  log =
    paused.log || [];

tripMemories =
  paused.memories ||
  tripMemories ||
  [];
  
  tripStartedAt =
    paused.startedAt ||
    new Date().toISOString();

  tripUpdatedAt =
    new Date().toISOString();

  tripStatus = "active";

  localStorage.removeItem(
    "platesPausedTrip"
  );

  save();
  render();

  toast("Game resumed");
}
  
function saveCurrentTrip(){

  var pausedTrip =
    activeTripData();

  delete pausedTrip.memories;

  try {

    localStorage.setItem(
      "platesPausedTrip",
      JSON.stringify(
        pausedTrip
      )
    );

    save();

    toast(
      "Trip saved for later"
    );

  } catch(err) {

    console.error(
      "Save Trip failed:",
      err
    );

    toast(
      "Trip could not be saved"
    );
  }
}
  
function shareText() {
  return "PLATES\n" + currentPlayer().name + " - " + tripName + "\n" +
    "I found " + collectedCount() + " of 50 states\n" +
    "Score: " + totalScore() + "\n" +
    "Badges: " + badgeCount(collectedCount()) + "\n" +
    "Top Finds: " + topFindsText();
}
var isSharing = false;

async function shareSummary() {
  if(navigator.share) navigator.share({ text:shareText() });
  else {
    navigator.clipboard.writeText(shareText());
    alert("Summary copied");
  }
}

function copyShareText() {
  navigator.clipboard.writeText(shareText());
  toast("Share text copied");
}


function formatShortDate(iso) {
  if(!iso) return "Unknown";

  var d = new Date(iso);

  if(isNaN(d.getTime())){
    return "Unknown";
  }

  return (
    (d.getMonth() + 1) +
    "/" +
    d.getDate() +
    "/" +
    String(d.getFullYear()).slice(-2)
  );
}

  
function stateHistory(code) {
  return log.filter(function(x){ return x.code === code; });
}

function firstFoundBy(code) {
  var history = stateHistory(code);
  if(!history.length) return "Not yet";
  var first = history[history.length - 1];
  return first.playerName || "Team";
}


function memoryDate(iso) {
  return formatShortDate(iso);
}



function stateNameForCode(code) {
  var btn = document.querySelector('.state[data-code="' + code + '"]');
  return btn ? btn.dataset.name : code;
}

function memoriesForState(code){
  return tripMemories.filter(function(m){
    return m.tripId === tripId &&
           m.stateCode === code;
  });
}
  

function renderCurrentTripPhotos() {

  var list =
    document.getElementById(
      "currentTripPhotosList"
    );

  if(!list) return;

  var photos =
    tripMemories.filter(
      function(memory) {

        return (
          memory.tripId === tripId &&
          memory.type === "photo" &&
          !memory.stateCode
        );

      }
    );

  if(!photos.length) {

    list.innerHTML =
      '<div class="memoryEmpty">' +
        'No photos added yet' +
      '</div>';

    return;
  }

  list.innerHTML =
    photos.map(
      function(memory) {

        return (
          '<div class="memoryItem">' +

            '<img ' +
              'class="memoryThumb" ' +
              'src="' +
              memory.photo +
              '" ' +
              'alt="Trip photo">' +

            '<div class="memoryText">' +

              '<div class="memoryTitle">' +
                (
                  memory.caption ||
                  "Trip photo"
                ) +
              '</div>' +

              '<div class="memoryDate">' +
                memoryDate(
                  memory.ts
                ) +
              '</div>' +

            '</div>' +

            '<button ' +
              'class="deleteMemoryBtn" ' +
              'type="button" ' +
              'onclick="deleteMemory(\'' +
                memory.id +
              '\')">' +
              'Delete' +
            '</button>' +

          '</div>'
        );

      }
    ).join("");

}


  
  function renderMemoryList(code) {
  var items = memoriesForState(code);

  if(!items.length) {
    return '<div class="memoryEmpty">No memories saved yet</div>';
  }

  return '<div class="memoryList">' +
    items.map(function(m) {
      var media =
        m.type === "photo" && m.photo
          ? '<img class="memoryThumb" src="' +
              m.photo +
              '" alt="Trip memory photo">'
          : '<div class="memoryNoteIcon">Note</div>';

      var body =
        m.type === "photo"
          ? (m.caption || "Photo memory")
          : (m.note || "");

      return (
        '<div class="memoryItem">' +
          media +
          '<div class="memoryText">' +
            '<div class="memoryTitle">' +
              (m.title || "Trip memory") +
            '</div>' +
            '<div class="memoryBody">' +
              body +
            '</div>' +
            '<div class="memoryDate">' +
              memoryDate(m.ts) +
            '</div>' +
          '</div>' +
          '<button class="deleteMemoryBtn" data-memory-id="' +
            m.id +
            '" type="button">Delete</button>' +
        '</div>'
      );
    }).join("") +
  '</div>';
}

function addMemoryNote(code) {
  var name = stateNameForCode(code);

  var title =
    prompt(
      "Memory title:",
      name + " sighting"
    );

  if(!title || !title.trim()) return;

  var note =
    prompt(
      "Add a note:",
      ""
    );

  if(note === null) return;

  tripMemories.unshift({
    id:
      "m" +
      Date.now() +
      Math.floor(
        Math.random() * 1000
      ),

    type: "note",

    tripId: tripId,
    trip: tripName,

    stateCode: code,
    stateName: name,

    title: title.trim(),
    note: (note || "").trim(),

    ts:
      new Date().toISOString()
  });

  save();
  render();
  selectMapState(code);

  toast("Memory saved");
}

function addMemoryPhoto(code) {
  pendingPhotoStateCode = code;

  var input =
    document.getElementById(
      "memoryPhotoInput"
    );

  if(input) {
    input.value = "";
    input.click();
  }
}


var memoryPhotoInput =
  document.getElementById(
    "memoryPhotoInput"
  );

if(memoryPhotoInput) {

  memoryPhotoInput.onchange =
    function() {

      var file =
        this.files &&
        this.files[0];

      if(file) {
        saveSelectedPhoto(
          file
        );
      }

    };

}
  

function saveSelectedPhoto(file) {
  if(!file || !pendingPhotoStateCode) return;

var code =
  pendingPhotoStateCode;

var isTripPhoto =
  code === "TRIP";

var name =
  isTripPhoto
    ? tripName
    : stateNameForCode(code);

  var reader =
    new FileReader();

  reader.onload =
    function(e) {
      var image =
        new Image();

      image.onload =
        function() {
          var maxSize = 900;
          var width = image.width;
          var height = image.height;

          if(
            width > height &&
            width > maxSize
          ) {
            height =
              Math.round(
                height *
                maxSize /
                width
              );

            width = maxSize;
          }

          if(
            height >= width &&
            height > maxSize
          ) {
            width =
              Math.round(
                width *
                maxSize /
                height
              );

            height = maxSize;
          }

          var canvas =
            document.createElement(
              "canvas"
            );

          canvas.width = width;
          canvas.height = height;

          var ctx =
            canvas.getContext("2d");

          ctx.drawImage(
            image,
            0,
            0,
            width,
            height
          );

          var compressedPhoto =
            canvas.toDataURL(
              "image/jpeg",
              0.72
            );

          var memoryOverlay =
            document.getElementById(
              "memoryOverlay"
            );

          var memoryPreview =
            document.getElementById(
              "memoryPreview"
            );

          var memoryCaptionInput =
            document.getElementById(
              "memoryCaptionInput"
            );

          var saveMemoryBtn =
            document.getElementById(
              "saveMemoryBtn"
            );

          var memoryCloseBtn =
            document.getElementById(
              "memoryCloseBtn"
            );

          if(
            !memoryOverlay ||
            !memoryPreview ||
            !memoryCaptionInput ||
            !saveMemoryBtn
          ) {
            toast(
              "Memory sheet could not open"
            );

            return;
          }

          memoryPreview.src =
            compressedPhoto;

          memoryPreview.classList.remove(
            "hidden"
          );

        memoryCaptionInput.value =
  isTripPhoto
    ? ""
    : name + " plate";

          memoryOverlay.classList.remove(
            "hidden"
          );

          setTimeout(
            function() {
              memoryCaptionInput.focus();
              memoryCaptionInput.select();
            },
            150
          );

          function closeMemorySheet() {
            memoryOverlay.classList.add(
              "hidden"
            );

            memoryPreview.src = "";

            memoryPreview.classList.add(
              "hidden"
            );

            memoryCaptionInput.value = "";

            pendingPhotoStateCode = "";
          }

          saveMemoryBtn.onclick =
            function() {
              var caption =
                memoryCaptionInput.value.trim();

              tripMemories.unshift({
                id:
                  "m" +
                  Date.now() +
                  Math.floor(
                    Math.random() *
                    1000
                  ),

                type: "photo",

                tripId: tripId,
                trip: tripName,

   stateCode:
  isTripPhoto
    ? ""
    : code,

stateName:
  isTripPhoto
    ? ""
    : name,

                
                title:
                  caption ||
                  "Photo memory",

                caption: caption,

                photo:
                  compressedPhoto,

                ts:
                  new Date().toISOString()
              });

              try {
                save();
              } catch(err) {
                tripMemories.shift();

                toast(
                  "Photo could not be saved"
                );

                return;
              }

              closeMemorySheet();


              render();

if(
  !isTripPhoto
){
  selectMapState(
    code
  );
}

toast(
  "Photo saved"
);

              
            };


if(memoryCloseBtn) {
  memoryCloseBtn.onclick =
    closeMemorySheet;
}

var cancelMemoryBtn =
  document.getElementById(
    "cancelMemoryBtn"
  );

if(cancelMemoryBtn) {
  cancelMemoryBtn.onclick =
    closeMemorySheet;
}

memoryOverlay.onclick =
  function(event) {
          
              if(
                event.target ===
                memoryOverlay
              ) {
                closeMemorySheet();
              }
            };
        };

      image.src = e.target.result;
    };

  reader.readAsDataURL(file);
}

function deleteMemory(id) {
  var item =
    tripMemories.find(
      function(m) {
        return m.id === id;
      }
    );

  if(!item) return;

  if(
    confirm(
      "Delete this memory?"
    )
  ) {
    tripMemories =
      tripMemories.filter(
        function(m) {
          return m.id !== id;
        }
      );

    save();
    render();

    if(selectedState) {
      selectMapState(
        selectedState
      );
    }

    toast("Memory deleted");
  }
}


function selectMapState(code) {
  selectedState = code;

  var btn = document.querySelector('.state[data-code="' + code + '"]');
  if(!btn) return;

  var name = btn.dataset.name;
  var pts = Number(btn.dataset.points);
  var seen = counts[code] || 0;
  var found = seen > 0;
  var history = stateHistory(code);
  var first = history.length ? history[history.length - 1] : null;


  var firstSeen = first && first.ts ? formatShortDate(first.ts) : (found ? "Unknown" : "Not yet");
  var firstTrip = first && first.trip ? first.trip : (found ? tripName : "Unknown");

  var mapTitle = document.getElementById("mapDetailsTitle");

if (mapTitle) {
  mapTitle.textContent = name;
}


var stateDetails = document.getElementById("stateDetails");
if(!stateDetails) return;

stateDetails.innerHTML =
  '<div class="stateDetailHero ' + (found ? "found" : "missing") + '">' +
    '<div><div class="stateDetailName">' + name + '</div>' +
    '<div class="stateDetailSub">' + (found ? "FOUND" : "MISSING") + '</div></div>' +
    '<div class="stateDetailCode">' + code + '</div>' +
  '</div>' +

  '<div class="detailGrid">' +
    '<div class="detailItem"><span>Rarity</span><strong>' + pts + '/10</strong></div>' +
    '<div class="detailItem"><span>Sightings</span><strong>' + seen + '</strong></div>' +
  '</div>' +

  '<div class="detailRows">' +
    '<div class="detailRow"><span>First Seen</span><strong>' + firstSeen + '</strong></div>' +
    '<div class="detailRow"><span>First Found By</span><strong>' + firstFoundBy(code) + '</strong></div>' +
    '<div class="detailRow"><span>First Roadtrip</span><strong>' + firstTrip + '</strong></div>' +
  '</div>' +

   '<div class="notesPreview">' +
    '<div class="title">Memories</div>' +
    '<div class="memoryActions">' +
      '<button class="memoryBtn memoryBtnPhoto" data-state-code="' + code + '" type="button">📸 Add Memory</button>' +
    '</div>' +
    renderMemoryList(code) +
  '</div>';
}

function renderBadges() {
  var badgeGrid = document.getElementById("badgeGrid");
  var badgeStats = document.getElementById("badgeStats");
  var nextBadgeBox = document.getElementById("nextBadgeBox");

  if (!badgeGrid) return;

  var unlocked = getUnlockedBadges().length;
  var total = badgeDefs.length;
  var badgeMini =
  document.getElementById("badgeMini");

var badgeTotal =
  document.getElementById("badgeTotal");

if(badgeMini){
  badgeMini.textContent = unlocked;
}

if(badgeTotal){
  badgeTotal.textContent = total;
}
  var percent = Math.round((unlocked / total) * 100);

  if (badgeStats) {
    badgeStats.innerHTML =
      '<div><strong>' + unlocked + '</strong><span>Unlocked</span></div>' +
      '<div><strong>' + (total - unlocked) + '</strong><span>Remaining</span></div>' +
      '<div><strong>' + percent + '%</strong><span>Complete</span></div>';
  }

  var next = getNextBadge();

  if (nextBadgeBox && next) {
    var progress = getBadgeProgress(next);
    var pct = Math.round((progress / next.goal) * 100);


    nextBadgeBox.innerHTML =
  '<div class="nextBadgeLabel">Next badge</div>' +
  '<div class="nextBadgeMain">' +
    '<div class="nextBadgeIcon">' + next.icon + '</div>' +
    '<div class="grow">' +
      '<div class="nextBadgeName">' + next.name + '</div>' +

'<div class="nextBadgeProgress">' +
  progress +
  ' / ' +
  next.goal +
  ' ' +
  next.unit +
'</div>' +
      
      '<div class="progressTrack">' +
        '<div class="progressFill" style="width:' + pct + '%;"></div>' +
      '</div>' +
    '</div>' +
  '</div>';
}

  var sorted = badgeDefs.slice().sort(function(a,b){
    return Number(isBadgeUnlocked(b)) - Number(isBadgeUnlocked(a)) ||
      (getBadgeProgress(b) / b.goal) - (getBadgeProgress(a) / a.goal);
  });

  badgeGrid.innerHTML = sorted.map(function(badge){
    var unlocked = isBadgeUnlocked(badge);
    var progress = getBadgeProgress(badge);
    var pct = Math.round((progress / badge.goal) * 100);

    return '<button class="badge ' + (unlocked ? 'unlocked' : 'locked') + '" data-badge-id="' + badge.id + '">' +
      '<div class="badgeIcon">' + (badge.hidden && !unlocked ? '❓' : badge.icon) + '</div>' +
      '<div class="badgeName">' + (badge.hidden && !unlocked ? 'Hidden Badge' : badge.name) + '</div>' +
      '<div class="badgeDesc">' + (badge.hidden && !unlocked ? 'Keep playing to discover...' : badge.desc) + '</div>' +
      '<div class="badgeMiniProgress">' + progress + ' / ' + badge.goal + '</div>' +
      '<div class="progressTrack small"><div class="progressFill" style="width:' + pct + '%"></div></div>' +
    '</button>';
  }).join("");
}


  
function tripModeSummaryText(c, points, sightings) {
  if(mode === "classic") return "Classic Mode";
  if(mode === "weighted") return "Weighted Mode";
  return "Unlimited Mode";
}


  
function deleteSavedTrip(index) {

  if(
    index < 0 ||
    index >= savedTrips.length
  ) {
    return;
  }

  var name =
    savedTrips[index].name ||
    "this roadtrip";

  showConfirmSheet({

    icon:"🗑",

    title:"Delete Trip",

    tripName:name,

    message:
      "This trip and its memories will be permanently deleted",

    buttonText:
      "Delete Trip",
danger:true,
    

    onConfirm:function(){

      savedTrips.splice(
        index,
        1
      );

      save();
      render();

      toast(
        "Trip deleted"
      );

    }

  });

}


  

function renameSavedTrip(index) {
  if(index < 0 || index >= savedTrips.length) return;
  var currentName = savedTrips[index].name || "Saved Roadtrip";
  var newName = prompt("Rename roadtrip:", currentName);
  if(newName && newName.trim()) {
    savedTrips[index].name = newName.trim();
    save();
    render();
    toast("Roadtrip renamed");
  }
}


function topFindsText() {
  var seen = [];
  document.querySelectorAll(".state").forEach(function(btn){
    var code = btn.dataset.code;
    if(counts[code] > 0) {
      seen.push({
        code:code,
        name:btn.dataset.name,
        points:Number(btn.dataset.points)
      });
    }
  });

  seen.sort(function(a,b){ return b.points - a.points; });
  if(!seen.length) return "No plates yet";
  return seen.slice(0,3).map(function(x){ return x.name; }).join(" - ");
}


function currentPlayer() {
  var player = players.find(function(p){ return p.id === currentPlayerId; });
  if(!player && players.length) {
    currentPlayerId = players[0].id;
    player = players[0];
  }
  return player || { id:"p1", name:"Dean" };
}

function timeAgo(iso) {
  var d = new Date(iso);
  var seconds = Math.floor((new Date() - d) / 1000);

  if(seconds < 60) return "Just now";

  var minutes = Math.floor(seconds / 60);
  if(minutes < 60) return minutes + "m ago";

  var hours = Math.floor(minutes / 60);
  if(hours < 24) return hours + "h ago";

  var days = Math.floor(hours / 24);
  return days + "d ago";
}

function addPlayer() {
  var name = prompt("Player Name:", "");
  if(!name || !name.trim()) return;

var player = {
  id:"p" + Date.now() + Math.floor(Math.random() * 1000),
  name:name.trim(),
  plate: cleanPlateName(name).slice(0,10),
  avatar:"🚗"
};

  players.push(player);
  currentPlayerId = player.id;
  save();
  render();
  toast("Player added");
}

function switchPlayer(id) {
  currentPlayerId = id;
  save();
  render();
  toast("Team Picker updated");
}

function deletePlayer(id) {
  if(players.length <= 1) {
    alert("Keep at least 1 Team Member");
    return;
  }

  var player = players.find(function(p){ return p.id === id; });
  if(!player) return;

  if(confirm("Delete " + player.name + "?")) {
    players = players.filter(function(p){ return p.id !== id; });
    if(currentPlayerId === id && players.length) currentPlayerId = players[0].id;
    save();
    render();
    toast("Player deleted");
  }
}

function playerStats() {
  var stats = {};

  players.forEach(function(p){
    stats[p.id] = {
      name:p.name,
      plates:0
    };
  });

  log.forEach(function(item){
    if(item.playerId && stats[item.playerId]) {
      stats[item.playerId].plates++;
    }
  });

  return Object.values(stats).sort(function(a,b){
    return b.plates - a.plates;
  });
}

  function playerPlateText(p) {
  if (p && p.plate) return cleanPlateName(p.plate).slice(0,8);
  if (p && p.name) return cleanPlateName(p.name).slice(0,8);
  return "PLAYER";
}


function playerCollectionStats(playerId){

  var states = {};
  var provinces = {};
  var plates = 0;

  log.forEach(function(item){

    if(
      !item ||
      item.playerId !== playerId ||
      !item.code
    ){
      return;
    }

    plates++;

    var btn =
      document.querySelector(
        '.state[data-code="' +
        item.code +
        '"]'
      );

    if(
      btn &&
      btn.dataset.canada === "true"
    ){
      provinces[item.code] = true;
    } else {
      states[item.code] = true;
    }

  });

  return {
    states:Object.keys(states).length,
    provinces:Object.keys(provinces).length,
    plates:plates
  };
}

function renderCollectionDetails(){

  var box =
    document.getElementById(
      "collectionDetails"
    );

  if(!box) return;

var statesRemaining =
  50 - collections.states.length;

var provincesRemaining =
  13 - collections.provinces.length;

  
  box.innerHTML =

    '<div class="quickStats">' +

'<div class="stat">' +
  '<strong>' +

    '<span class="found" ' +
      'style="display:inline;font-size:inherit;">' +

      collections.states.length +
      '/' +

    '</span>' +

    '50' +

  '</strong>' +

  '<span>🇺🇸 States</span>' +
'</div>' +

'<div class="stat">' +
  '<strong>' +

    '<span class="found" ' +
      'style="display:inline;font-size:inherit;">' +

      collections.provinces.length +
      '/' +

    '</span>' +

    '13' +

  '</strong>' +

  '<span>🇨🇦 Provinces</span>' +
'</div>' +

'<div class="stat">' +
  '<strong>' +

    '<span class="found" ' +
      'style="display:inline;font-size:inherit;">' +

      (collections.plates || 0) +

    '</span>' +

  '</strong>' +

  '<span>👀 Plates</span>' +
'</div>'
    '</div>' +

  '<div class="card" style="margin-top:16px;">' +

 '<div style="' +
  'text-align:center;' +
  'font-size:18px;' +
  'font-weight:700;' +
  'color:var(--muted);' +
  'line-height:1.45;">' +
    

    statesRemaining +
    ' states to go<br>' +

    provincesRemaining +
    ' provinces to go' +

  '</div>' +

'</div>';


}
  

function openCollectionSheet(){

renderCollectionDetails();
  
  var overlay =
    document.getElementById(
      "collectionOverlay"
    );

  if(!overlay){
    toast("Collection overlay not found");
    return;
  }

  overlay.classList.remove("hidden");
}

  
function closeCollectionSheet(){

  document
    .getElementById("collectionOverlay")
    .classList.add("hidden");
}
  
function renderFamily(c, unlockedBadges) {
  var player = currentPlayer();

  var familyCount = document.getElementById("familyCount")

  var board = document.getElementById("leaderboardList");
var standingsTitle = document.getElementById("standingsTitle");
if(standingsTitle) {
  standingsTitle.textContent =
    "Team Standings · " +
    mode.charAt(0).toUpperCase() +
    mode.slice(1) +
    " Mode";
}
var standingsModeLabel = document.getElementById("standingsModeLabel");
if(standingsModeLabel) {
  standingsModeLabel.textContent =
    mode === "classic" ? "Classic Mode" :
    mode === "weighted" ? "Battle Mode" :
    "Roadtrip Mode";
}

  if(board) {
    var standings = playerStats();

    board.innerHTML = standings.map(function(p,i){
      var medal = i === 0 ? "1st" : i === 1 ? "2nd" : i === 2 ? "3rd" : (i + 1) + "th";

return '<div class="row battleRow">' +
  '<div class="battleRank">' + medal + '</div>' +
  '<div class="grow">' +
    '<div class="title battlePlayer">' +
      ((players.find(function(x){ return x.name === p.name; }) || {}).avatar || "🚗") +
      ' ' +
      playerPlateText(players.find(function(x){ return x.name === p.name; })) +
    '</div>' +
  '</div>' +
  '<div class="battleScore">' + p.plates + ' plates</div>' +
'</div>';

    }).join("");
  }

  var list = document.getElementById("familyList");
  if(list) {
    if(!players.length) {
      list.innerHTML = '<div class="familyEmpty">No Members yet</div>';
      return;
    }

    list.innerHTML = players.map(function(p){
      
      
      var playerCollection =
  playerCollectionStats(p.id);
      
      var initial = (p.name || "?").trim().charAt(0).toUpperCase();

return '<div class="familyRow ' + (p.id === currentPlayerId ? "active" : "") + '">' +

'<div class="playerAvatar">' +
  (p.avatar || "🚗") +
'</div>' +

'<div class="familyInfo">' +

'<div class="familyName">' +
p.name +
'</div>' +

'<div class="familyMeta">' +
(p.id === currentPlayerId
  ? 'You'
  : 'Friend') +
'</div>' +


'<div class="familyStats">' +

'🇺🇸 ' +
playerCollection.states +
' states • ' +

'🇨🇦 ' +
playerCollection.provinces +
' provinces • ' +

'👀 ' +
playerCollection.plates +
' plates' +

'</div>' +  
  
'</div>' +
  
(p.id === currentPlayerId
? ''
: '<button class="familySmallBtn familyDeleteBtn" data-player-delete="' + p.id + '" type="button">Delete</button>') +
'</div>' +
'</div>';
    }).join("");
  }
}

function checkTripCompletion() {
  var totalStates =
    Object.keys(counts).filter(function(s) {
      return counts[s] > 0;
    }).length;

  if(totalStates === 50 && !hasShownCompletion) {
    hasShownCompletion = true;
    localStorage.platesCompletionShown = "true";

    var overlay =
      document.getElementById("completionOverlay");

    if(overlay) {
      overlay.classList.remove("hidden");
    }
  }
}


var badgeDefs = [
  {
    id:"firstPlate",
    icon:"🧢",
    name:"Rookie Card",
    desc:"Collect your first state",
    goal:1,
    type:"states",
    unit:"state found"
  },

  {
    id:"explorer",
    icon:"🧭",
    name:"10 Spot",
    desc:"Find 10 states in 1 trip",
    goal:10,
    type:"states",
    unit:"states found"
  },

  {
    id:"roadWarrior",
    icon:"🏆",
    name:"Road Warrior",
    desc:"Find 20 states in 1 trip",
    goal:20,
    type:"states",
    unit:"states found"
  },

  {
    id:"halfway",
    icon:"🧩",
    name:"Halfway Home",
    desc:"Collect 25 states",
    goal:25,
    type:"states",
    unit:"states found"
  },

  {
    id:"coastToCoast",
    icon:"🌊",
    name:"Coast to Coast",
    desc:"Spot both California & Maine",
    goal:2,
    type:"collection",
    codes:["CA","ME"],
    unit:"states found"
  },

  {
    id:"ohCanada",
    icon:"🍁",
    name:"Oh, Canada",
    desc:"Find your first Canadian province",
    goal:1,
    type:"canada",
    unit:"province found"
  },

  {
    id:"clearlyCanadian",
    icon:"🇨🇦",
    name:"Clearly Canadian",
    desc:"Spot all Canadian provinces & territories",
    goal:13,
    type:"canada",
    unit:"provinces found"
  },

  {
    id:"rushHour",
    icon:"🚦",
    name:"Rush Hour",
    desc:"Find 10 plates in 60 minutes or less",
    goal:10,
    type:"rushHour",
    unit:"plates found"
  },

  {
    id:"fourCorners",
    icon:"🗺️",
    name:"4 Corners",
    desc:"Spot Arizona, Colorado, New Mexico & Utah in 1 trip",
    goal:4,
    type:"collection",
    codes:["AZ","CO","NM","UT"],
    unit:"states found"
  },

  {
    id:"newEnglander",
    icon:"🦞",
    name:"New Englander",
    desc:"Find all 6 New England states in 1 trip",
    goal:6,
    type:"collection",
    codes:["MA","CT","RI","NH","VT","ME"],
    unit:"states found"
  },

  {
    id:"heartlander",
    icon:"🌽",
    name:"Heartlander",
    desc:"Find Iowa, Kansas, Nebraska & Missouri in 1 trip",
    goal:4,
    type:"collection",
    codes:["IA","KS","NE","MO"],
    unit:"states found"
  },

  {
    id:"mountainMover",
    icon:"🏔️",
    name:"Mountain Mover",
    desc:"Find Colorado, Utah, Wyoming, Montana & Idaho in 1 trip",
    goal:5,
    type:"collection",
    codes:["CO","UT","WY","MT","ID"],
    unit:"states found"
  },

  {
    id:"og",
    icon:"🗽",
    name:"OG",
    desc:"Find all 13 original states",
    goal:13,
    type:"collection",
    codes:[
      "DE","PA","NJ","GA","CT","MA","MD",
      "SC","NH","VA","NY","NC","RI"
    ],
    unit:"states found"
  },

  {
    id:"battleTested",
    icon:"⚔️",
    name:"Battle Tested",
    desc:"Win a battle",
    goal:1,
    type:"battleWins",
    unit:"battle won"
  },

  {
    id:"frequentFlyer",
    icon:"✈️",
    name:"Frequent Flyer",
    desc:"Complete 10 total trips",
    goal:10,
    type:"completedTrips",
    unit:"trips completed"
  },

  {
    id:"complete50",
    icon:"🇺🇸",
    name:"DC United",
    desc:"Find all 50 states + Washington DC",
    goal:51,
    type:"statesPlusDC", 
    unit:"states found"
  },

  {
    id:"hidden1",
    icon:"❓",
    name:"Hidden Badge",
    desc:"Keep playing to discover this badge",
    goal:1,
    type:"hidden",
    hidden:true,
    unit:""
  }
];


function countCollectedCodes(codes) {
  return codes.filter(function(code){
    return !!counts[code];
  }).length;
}


function getRushHourProgress() {
  if(!Array.isArray(log) || !log.length) {
    return 0;
  }

  var timedSightings =
    log
      .filter(function(item){
        return item && item.ts;
      })
      .map(function(item){
        return new Date(item.ts).getTime();
      })
      .filter(function(time){
        return !isNaN(time);
      })
      .sort(function(a,b){
        return a - b;
      });

  var best = 0;
  var start = 0;
  var oneHour = 60 * 60 * 1000;

  for(
    var end = 0;
    end < timedSightings.length;
    end++
  ){
    while(
      timedSightings[end] -
      timedSightings[start] >
      oneHour
    ){
      start++;
    }

    best =
      Math.max(
        best,
        end - start + 1
      );
  }

  return Math.min(best, 10);
}


function getBadgeProgress(badge) {
  var c = collectedCount();

  if(badge.type === "states") {
    return Math.min(c, badge.goal);
  }

  if(badge.type === "statesPlusDC") {
  var hasDC = counts.DC > 0 ? 1 : 0;

  return Math.min(
    collectedCount() + hasDC,
    badge.goal
  );
}

  if(badge.type === "collection") {
    return countCollectedCodes(
      badge.codes || []
    );
  }

  if(badge.type === "canada") {
    return Math.min(
      canadaCollectedCount(),
      badge.goal
    );
  }

  if(badge.type === "rushHour") {
    return getRushHourProgress();
  }

  if(badge.type === "completedTrips") {
    return Math.min(
      savedTrips.length,
      badge.goal
    );
  }

  if(badge.type === "battleWins") {
    return Math.min(
      Number(
        localStorage.platesBattleWins || 0
      ),
      badge.goal
    );
  }

  return 0;
}

function isBadgeUnlocked(badge) {
  return getBadgeProgress(badge) >= badge.goal;
}

function getUnlockedBadges() {
  return badgeDefs.filter(isBadgeUnlocked);
}

function getNextBadge() {
  return badgeDefs
    .filter(function(b){ return !b.hidden && !isBadgeUnlocked(b); })
    .sort(function(a,b){
      return (getBadgeProgress(b) / b.goal) - (getBadgeProgress(a) / a.goal);
    })[0];
}


function formatTripDate(dateStr){

  if(!dateStr) return "";

  var date =
    new Date(dateStr);

  if(isNaN(date.getTime())){
    return "";
  }

  return (
    (date.getMonth() + 1) +
    "/" +
    date.getDate() +
    "/" +
    String(date.getFullYear()).slice(-2)
  );

}
  

function addActivity(text) {
  var activityFeed =
    safeParse(
      localStorage.getItem(
        "platesActivityFeed"
      ),
      "[]"
    );

  activityFeed.unshift({
    text: text,
    ts: new Date().toISOString()
  });

  activityFeed =
    activityFeed.slice(0, 25);

  localStorage.setItem(
    "platesActivityFeed",
    JSON.stringify(activityFeed)
  );
}

function renderCollections() {
  var states =
    document.getElementById(
      "lifeStates"
    );

  var provinces =
    document.getElementById(
      "lifeProvinces"
    );

  var plates =
    document.getElementById(
      "lifePlates"
    );

  if(states){
    states.textContent =
      collections.states.length;
  }

  if(provinces){
    provinces.textContent =
      collections.provinces.length;
  }

  if(plates){
    plates.textContent =
      collections.plates || 0;
  }
}

  
  function renderActivityFeed() {

  var box =
    document.getElementById(
      "activityFeed"
    );

  if(!box) return;

  var feed =
    safeParse(
      localStorage.getItem(
        "platesActivityFeed"
      ),
      "[]"
    );

  if(!feed.length){
    box.innerHTML =
      '<div class="memoryEmpty">' +
      'No recent activity yet' +
      '</div>';
    return;
  }

  box.innerHTML =
    feed
      .slice(0,5)
      .map(function(item){

        return (
          '<div class="recentItem">' +

            '<div class="recentState">' +
              item.text +
            '</div>' +

            '<div class="recentFinder">' +
              timeAgo(item.ts) +
            '</div>' +

          '</div>'
        );

      })
      .join("");

}

function render() {

var savedVote =
  localStorage.getItem(
  getDebateVoteKey()
)

if(savedVote){

  var selected =
    document.querySelector(
      '.debateBtn[data-vote="' +
      savedVote +
      '"]'
    );

  if(selected){
    selected.classList.add("selected");
  }
}

  var inviteCodeEl = document.getElementById("tripInviteCode");
  if(inviteCodeEl) {
    inviteCodeEl.textContent = getTripInviteCode();
  }

  var accountBox = document.getElementById("accountBox");
var createAccountBtn = document.getElementById("createAccountBtn");

var unlockedBadges = getUnlockedBadges().length;

if(accountBox) {
  if(isSignedIn()) {

accountBox.innerHTML =
  '<div class="profileHero">' +

    '<div class="profileAvatar">' +
      (profile.avatar || "🚗") +
    '</div>' +

    '<div class="profileName">' +
      account.username +
    '</div>' +


    '<div class="profileLevel">' +
      unlockedBadges + ' Badge' +
      (unlockedBadges === 1 ? '' : 's') +
      ' Earned' +
    '</div>' +

  '</div>';

  } else {
    accountBox.innerHTML =
      '<div class="memoryEmpty">Play with and against friends, compete globally & more!</div>';
  }
}

if(createAccountBtn) {
  createAccountBtn.textContent = isSignedIn() ? "✏️ Edit Account" : "👤 Create Account";
}


  var modeDropdownText = document.getElementById("modeDropdownText");

if(modeDropdownText) {
  modeDropdownText.textContent = gameSummaryLabel();
}


var tripModeTop = document.getElementById("tripModeTop");

if(tripModeTop) {
  tripModeTop.textContent = gameSummaryLabel();
}

var c = collectedCount();
var pct = Math.round(c / 50 * 100);
var points = totalScore();
var sightings = totalSightings();
var left = Math.max(0, 50 - c);

var listCountEl =
  document.getElementById(
    "listCount"
  );

if(listCountEl){

  var countText =
 countText =
  '<span class="homeFoundNumber">' +
  c +
  '/</span>' +
  '<span class="homeFoundRest">50 found</span>';

  if(mode !== "classic"){

    countText +=
      ' <span class="countDivider">•</span> ' +
      '<span class="homeScoreTotal">' +
      points +
      ' pts' +
      '</span>';
  }

  listCountEl.innerHTML =
    countText;
}

var canadaCountEl =
  document.getElementById(
    "canadaCount"
  );

if(canadaCountEl){

  var canadaTotal =
    canadaCollectedCount();

  canadaCountEl.innerHTML =
    '<span class="found">' +
    canadaTotal +
    '/</span>13';
}
  



  
document.body.classList.toggle(
  "show-rarity",
  mode !== "classic"
);

var highValueLegend =
  document.getElementById(
    "highValueLegend"
  );

if(highValueLegend){

  highValueLegend.classList.toggle(
    "hidden",
    mode === "classic"
  );
}

document.querySelectorAll(".modeExplainCard").forEach(function(card){
  card.classList.toggle("active", card.dataset.explainMode === mode);
});
  document.querySelectorAll(".modeExplainCard").forEach(function(card){
  card.onclick = function(){
    setMode(card.dataset.explainMode);
  };
});


  document
  .querySelectorAll(
    ".screen"
  )
  .forEach(
    function(screen) {
      screen.classList.add(
        "hidden"
      );
    }
  );

var activeScreen =
  document.getElementById(
    view + "Screen"
  );

if(!activeScreen) {

  view = "trips";

  activeScreen =
    document.getElementById(
      "tripsScreen"
    );

  localStorage.platesView =
    view;
}

activeScreen.classList.remove(
  "hidden"
);

document
  .querySelectorAll(
    ".navInner button"
  )
  .forEach(
    function(button) {
      button.classList.remove(
        "active"
      );
    }
  );

var activeNav =
  document.getElementById(
    view + "Nav"
  );

if(activeNav) {
  activeNav.classList.add(
    "active"
  );
}


  

["classic","weighted","unlimited"].forEach(function(m){
  
  
  var modeBtn = document.getElementById(m + "Btn");
  if(modeBtn) {
    modeBtn.classList.toggle("active", mode === m);
  }
});

  document.querySelectorAll(".state").forEach(function(btn){
    var code = btn.dataset.code;
    btn.classList.toggle("collected", counts[code] > 0);
    btn.classList.toggle("rare", Number(btn.dataset.points) >= 8);
    var old = btn.querySelector(".value");
    if(old) old.remove();
    if(mode !== "classic") {
      var val = document.createElement("span");
      val.className = "value";
      val.textContent = btn.dataset.points + " pts";
      btn.appendChild(val);
    }
  });

  document.querySelectorAll("[data-map-code]").forEach(function(cell){
    var code = cell.dataset.mapCode;
    var stateButton = document.querySelector('.state[data-code="' + code + '"]');
    var pts = stateButton ? Number(stateButton.dataset.points) : 0;
    cell.classList.toggle("hit", counts[code] > 0);
    cell.classList.toggle("rare", pts >= 8);
  });

var primaryNumberEl = document.getElementById("primaryNumber");
var outOfEl = document.getElementById("outOf");
var primaryLabelEl = document.getElementById("primaryLabel");
var progressBarEl = document.getElementById("progressBar");
var fillEl = document.getElementById("fill");
var bonusEl = document.getElementById("bonusCount");

if(mode === "classic") {

  if(primaryNumberEl){
    primaryNumberEl.textContent = c;
  }

  if(outOfEl){
  outOfEl.style.display = "inline";
  outOfEl.innerHTML = '<span class="found">/</span>50';
}


  if(primaryLabelEl){
    primaryLabelEl.textContent = "states found";
  }


    
  if(bonusEl){
    var bonus = bonusCollectedCount();

    bonusEl.textContent =
      bonus > 0
        ? "+" + bonus + " Bonus Plate" + (bonus > 1 ? "s" : "")
        : "";
  }

 if(progressBarEl){
  progressBarEl.style.display = "block";
}

if(fillEl){
  fillEl.style.width = pct + "%";
}

  if(fillEl){
    fillEl.style.width = pct + "%";
  }
}

if(mode === "weighted") {

  if(primaryNumberEl){
    primaryNumberEl.textContent = points;
  }

  if(outOfEl){
    outOfEl.style.display = "none";
  }

  if(primaryLabelEl){
    primaryLabelEl.textContent = "points";
  }

  if(bonusEl){
    bonusEl.textContent = "";
  }

if(progressBarEl){
  progressBarEl.style.display = "block";
}

if(fillEl){
  fillEl.style.width = pct + "%";
}
}

if(mode === "unlimited") {

  if(primaryNumberEl){
    primaryNumberEl.textContent = points;
  }

  
  if(outOfEl){
    outOfEl.style.display = "none";
  }

  if(primaryLabelEl){
    primaryLabelEl.textConte

    nt = sightings + " sightings";
  }

  if(bonusEl){
    bonusEl.textContent = "";
  }

if(progressBarEl){
  progressBarEl.style.display = "block";
}

if(fillEl){
  fillEl.style.width = pct + "%";
}
}

updateBestForCurrentMode();

var bestTripEl =
  document.getElementById("bestTrip");

if(bestTripEl){
  bestTripEl.textContent =
    bestForCurrentMode();
}

  
var tripCountEl =
  document.getElementById("tripCount");

if(tripCountEl){
  tripCountEl.textContent =
    tripCount;
}

var mapCountEl =
  document.getElementById("mapCount");

if(mapCountEl){
  mapCountEl.innerHTML =
    '<span class="found">' +
    c +
    '/</span>50 Found';
}

var mapModeSummary =
  document.getElementById(
    "mapModeSummary"
  );

if(mapModeSummary){
  mapModeSummary.textContent =
    gameType.charAt(0).toUpperCase() +
    gameType.slice(1) +
    " • " +
    scoringModeLabel();
}

var badgeMini =
  document.getElementById("badgeMini");

if(badgeMini){
  badgeMini.textContent =
    unlockedBadges;
}

var profileBadgeMini =
  document.getElementById(
    "profileBadgeMini"
  );

if(profileBadgeMini){
  profileBadgeMini.textContent =
    unlockedBadges;
}

renderFamily(c, unlockedBadges);

/* HOME HERO */

var tripNameTopEl =
  document.getElementById("tripNameTop");

if(tripNameTopEl){
  tripNameTopEl.textContent =
    tripName;
}


  var tripGameTypeTop =
  document.getElementById(
    "tripGameTypeTop"
  );

if(tripGameTypeTop){
  tripGameTypeTop.textContent =
    gameTypeLabel() + " Mode";
}

var tripScoringTop =
  document.getElementById(
    "tripScoringTop"
  );

if(tripScoringTop){
  tripScoringTop.textContent =
    scoringModeLabel() + " Scoring";
}

var activeGameLabelTop =
  document.getElementById(
    "activeGameLabelTop"
  );

if(activeGameLabelTop){
  activeGameLabelTop.textContent =
    "Active Trip • Started " +
    new Date(tripStartedAt)
      .toLocaleDateString(
        "en-US"
      );
}


/* TRIPS HERO */

  /* TRIPS HERO */

var tripNameEl =
  document.getElementById("tripName");

var activeGameLabelTrips =
  document.getElementById(
    "activeGameLabelTrips"
  );

if(activeGameLabelTrips){
  activeGameLabelTrips.textContent =
    "Active Trip • Started " +
    new Date(tripStartedAt)
      .toLocaleDateString(
        "en-US"
      );
}
  
var tripScoringTrips =
  document.getElementById("tripScoringTrips");

var tripPrimaryNumber =
  document.getElementById("tripPrimaryNumber");

var tripBonusCount =
  document.getElementById("tripBonusCount");

var tripFoundText =
  document.getElementById("tripFoundText");
  
var tripProgressBar =
  document.getElementById("tripProgressBar");

var tripProgressFill =
  document.getElementById("tripProgressFill");


if(tripNameEl){
  tripNameEl.textContent =
    tripName;
}

if(tripGameTypeTrips){
  tripGameTypeTrips.textContent =
    gameTypeLabel() + " Mode";
}

if(tripScoringTrips){
  tripScoringTrips.textContent =
    scoringModeLabel() + " Scoring";
}


if(mode === "classic"){

  if(tripPrimaryNumber){
    tripPrimaryNumber.textContent = c;
  }

  if(tripBonusCount){
    var tripBonus =
      bonusCollectedCount();

    tripBonusCount.textContent =
      tripBonus > 0
        ? "+" + tripBonus +
          " Bonus Plate" +
          (tripBonus === 1 ? "" : "s")
        : "";
  }

  if(tripProgressBar){
    tripProgressBar.style.display =
      "block";
  }

  if(tripProgressFill){
    tripProgressFill.style.width =
      pct + "%";
  }
}

if(mode === "weighted"){

  if(tripPrimaryNumber){
    tripPrimaryNumber.textContent =
      c;
  }

  if(tripBonusCount){
    tripBonusCount.textContent =
      points + " pts";
  }

  if(tripFoundText){
    tripFoundText.textContent =
      "states found";
  }

  if(tripProgressBar){
    tripProgressBar.style.display =
      "block";
  }

  if(tripProgressFill){
    tripProgressFill.style.width =
      pct + "%";
  }
}


if(mode === "unlimited"){

  if(tripPrimaryNumber){
    tripPrimaryNumber.textContent =
      sightings;
  }

  if(tripBonusCount){
    tripBonusCount.textContent = "";
  }

  if(tripFoundText){
    tripFoundText.textContent =
      "plates found";
  }

  if(tripProgressBar){
    tripProgressBar.style.display =
      "none";
  }
}


if(mode !== "weighted" &&
   mode !== "unlimited"){

  if(tripFoundText){
    tripFoundText.textContent =
      "states found";
  }
}

  document.getElementById("historyCount").textContent = savedTrips.length + " saved";


  var hasActiveGame = tripName && tripName.trim() !== "";

var currentTripHeader = document.querySelector(".currentTripHeader");
var noGameHero = document.getElementById("noGameHero");

if(currentTripHeader && noGameHero) {
  if(hasActiveGame) {
    currentTripHeader.classList.remove("hidden");
    noGameHero.classList.add("hidden");
  } else {
    currentTripHeader.classList.add("hidden");
    noGameHero.classList.remove("hidden");
  }
}


  
var historyHtml = savedTrips.length ? savedTrips.map(function(t, i){

  var label =
  t.mode === "classic"
    ? t.states + "/50 states"
    : t.mode === "weighted"
      ? t.states + "/50 states<br>" + t.score + " points"
      : t.score + " points";


var memoryCount =
  (t.memories || []).length;

if(memoryCount > 0){
  label +=
    '<br>📸 ' +
    memoryCount +
    ' memor' +
    (memoryCount === 1 ? 'y' : 'ies');
}



  

return '<div class="row tripRow savedTripCard" data-trip-index="' + i + '">' +
  
  '<div class="grow">' +
    '<div class="title tripHistoryTitle">' + t.name + '</div>' +


'<div class="tripMeta">' +

  '<div class="tripHistoryDate">' +

    (
      formatTripDateRange(
        t.startedAt,
        t.endedAt
      ) ||
      t.date ||
      "Date unavailable"
    ) +

  '</div>' +

  '<div class="tripHistoryStats">' +

    '<div>🎯 ' +
      (
        t.mode.charAt(0).toUpperCase() +
        t.mode.slice(1)
      ) +
    '</div>' +

    '<div>🇺🇸 ' +
      t.states +
      "/50 states" +
    '</div>' +

    '<div>⭐ ' +
      t.score +
      " points" +
    '</div>' +

  '</div>' +

'</div>' +
  

'<div class="tripRowActions">' +

  '<button class="textBtn shareTripBtnSmall resumeTripBtn" data-trip-index="' +
    i +
    '" type="button">▶ Resume</button>' +

  '<button class="textBtn memoriesTripBtn" data-trip-index="' +
    i +
    '" type="button">📸 Memories</button>' +

  '<button class="textBtn shareTripBtnSmall" data-trip-index="' +
    i +
    '" type="button">📤 Share</button>' +

  '<button class="textBtn deleteTripBtn deleteSavedTripBtn" data-trip-index="' +
    i +
    '" type="button">🗑 Delete</button>' +

'</div>' +

  
'</div>' +
'</div>';

}).join("") : '<div class="emptyHistory">No saved roadtrips yet.</div>';

var tripHistoryListEl = document.getElementById("tripHistoryList");

if (tripHistoryListEl) {
  tripHistoryListEl.innerHTML = historyHtml;

  tripHistoryListEl.onclick = function(e) {
    var resumeBtn =
      e.target.closest(".resumeTripBtn");

if (resumeBtn) {
  resumeSavedTrip(
    parseInt(
      resumeBtn.dataset.tripIndex,
      10
    )
  );

  return;
}

var memoriesBtn =
  e.target.closest(
    ".memoriesTripBtn"
  );

if(memoriesBtn){

  openTripDetails(
    parseInt(
      memoriesBtn.dataset.tripIndex,
      10
    )
  );

  return;
}
    
var deleteBtn =
  e.target.closest(".deleteSavedTripBtn");

if (deleteBtn) {
  deleteSavedTrip(
    parseInt(
      deleteBtn.dataset.tripIndex,
      10
    )
  );

  return;
}

var shareBtn =
  e.target.closest(".shareTripBtnSmall");


if (
  shareBtn &&
  !shareBtn.classList.contains("resumeTripBtn") &&
  !shareBtn.classList.contains("deleteSavedTripBtn")
) {

  shareSavedTrip(
    parseInt(
      shareBtn.dataset.tripIndex,
      10
    )
  )

  return

}


var tripCard =
  e.target.closest(
    ".savedTripCard"
  )

if(tripCard){

  openTripDetails(
    parseInt(
      tripCard.dataset.tripIndex,
      10
    )
  )

}
    
    
    
  };
}

var recentEl = document.getElementById("recent");

if (recentEl) {
  recentEl.innerHTML = log.length ? log.slice(0,4).map(function(x){
    var pts = mode === "classic" ? "" : "+" + x.points;
    var finder = x.playerName || "Team";
    return '<div class="row recentItem"><div><div class="recentState">' + x.name + '</div><div class="recentFinder">Found by ' + finder + '</div></div><div class="recentMeta"><span class="recentTime">' + timeAgo(x.ts) + '</span><span class="recentPts">' + pts + '</span></div></div>';
  }).join("") : '<div class="memoryEmpty">No plates yet<br><br>Tap a state to start your roadtrip</div>';
}

renderDailyChallenge();
renderBadges(c);
renderCollections();
renderActivityFeed();

  var xpTitle =
  document.getElementById(
    "xpTitle"
  );

var xpText =
  document.getElementById(
    "xpText"
  );

var xpFill =
  document.getElementById(
    "xpFill"
  );

var level =
  getPlayerLevel();

var levelXP =
  playerXP % 100;

if(xpTitle){
  xpTitle.textContent =
    "Level " + level;
}

if(xpText){
  xpText.textContent =
    levelXP +
    "/100 XP • " +
    (100 - levelXP) +
    " XP to Level " +
    (level + 1);
}

  if(xpFill){

  var fillPct =
    levelXP === 0
      ? 0
      : Math.max(levelXP, 5);

  xpFill.style.width =
    fillPct + "%";
}



  
  var top = log.slice().sort(function(a,b){ return b.points - a.points; })[0];
  document.getElementById("shareTripName").textContent = tripName;
  document.getElementById("shareDate").textContent = new Date().toLocaleDateString();
  document.getElementById("shareModeLabel").textContent = mode;
  document.getElementById("shareStates").textContent = c + "/50";
  document.getElementById("shareScore").textContent = points;
  document.getElementById("shareBadges").textContent = unlockedBadges;
  if(document.getElementById("shareProgressLine")) {
    document.getElementById("shareProgressLine").textContent = "I found " + c + " of 50 states";
  }
  if(document.getElementById("shareTopFinds")) {
    document.getElementById("shareTopFinds").textContent = topFindsText();
  }
  if(document.getElementById("shareTopFind")) {
    document.getElementById("shareTopFind").textContent = top ? top.name + " (" + top.code + ") - " + top.points + " pts" : "No plates yet";
  }

  document.querySelectorAll(".renameTripBtnSmall").forEach(function(btn){
    btn.onclick = function(e){
      e.stopPropagation();
      renameSavedTrip(Number(btn.dataset.tripIndex));
    };
  });

  document.querySelectorAll(".deleteTripBtn").forEach(function(btn){
    btn.onclick = function(e){
      e.stopPropagation();
      deleteSavedTrip(Number(btn.dataset.tripIndex));
    };
  });

  var currentTripRow = document.querySelector(".currentTripRow");
  if(currentTripRow) {
    currentTripRow.onclick = function(){
      setView("game");
    };
  }

  if(selectedState) selectMapState(selectedState);

  save();
}


  
function openBadgeDetail(badge) {
  var progress = getBadgeProgress(badge);
  var pct = Math.round((progress / badge.goal) * 100);
  var unlocked = isBadgeUnlocked(badge);

  document.getElementById("badgeDetailIcon").textContent =
    badge.hidden && !unlocked ? "❓" : badge.icon;

  document.getElementById("badgeDetailName").textContent =
    badge.hidden && !unlocked ? "Hidden Badge" : badge.name;

  document.getElementById("badgeDetailDesc").textContent =
    badge.hidden && !unlocked ? "Keep playing to discover this badge." : badge.desc;

  document.getElementById("badgeDetailProgress").textContent =
    progress + " / " + badge.goal + (unlocked ? " complete" : "");

  document.getElementById("badgeDetailFill").style.width = pct + "%";

  document.getElementById("badgeOverlay").classList.remove("hidden");
}

  

function checkForResumeTrip() {

  var hasProgress =
    collectedCount() > 0 ||
    log.length > 0;

  if(!hasProgress) {
    return;
  }

  var overlay =
    document.getElementById(
      "resumeGameOverlay"
    );

  if(overlay) {
    overlay.classList.remove(
      "hidden"
    );
  }
}



  
function attachHandlers() {

document
  .querySelectorAll(".navInner button")
  .forEach(function(btn) {

    btn.onclick = function() {
      setView(btn.dataset.view);
    };

  });
  
var nextTripNameCloseBtn =
  document.getElementById(
    "nextTripNameCloseBtn"
  );

if(nextTripNameCloseBtn){

  nextTripNameCloseBtn.onclick =
    function(){

      closeNextTripNameSheet();

    };
}

var nextTripNameClearBtn =
  document.getElementById(
    "nextTripNameClearBtn"
  );

if(nextTripNameClearBtn){

  nextTripNameClearBtn.onclick =
    function(){

      var input =
        document.getElementById(
          "nextTripNameInput"
        );

      if(input){
        input.value = "";
        input.focus();
      }
    };
}


var nextTripNameSaveBtn =
  document.getElementById(
    "nextTripNameSaveBtn"
  );

if(nextTripNameSaveBtn){

  nextTripNameSaveBtn.onclick =
    saveNextTripName;
}

  var tripNameCloseBtn =
  document.getElementById(
    "tripNameCloseBtn"
  );

if(tripNameCloseBtn){

  tripNameCloseBtn.onclick =
    closeTripNameSheet;
}



  
  var saveTripNameBtn =
  document.getElementById(
    "saveTripNameBtn"
  );

if(saveTripNameBtn){

  saveTripNameBtn.onclick =
    function(){

      var value =
        document
          .getElementById(
            "tripNameInput"
          )
          .value
          .trim();

      if(!value) return;

      tripName = value;

      save();

      render();

      closeTripNameSheet();

      toast(
        "Trip renamed"
      );
    };
}

  var tripNameInput =
  document.getElementById(
    "tripNameInput"
  );

if(tripNameInput){

  tripNameInput.onkeydown =
    function(e){

      if(e.key === "Enter"){

        e.preventDefault();

        if(saveTripNameBtn){
          saveTripNameBtn.click();
        }
      }
    };
}

  

  

var nextTripNameInput =
  document.getElementById(
    "nextTripNameInput"
  );

  

if(nextTripNameInput){

  nextTripNameInput.onkeydown =
    function(e){

      if(e.key === "Enter"){
        saveNextTripName();
      }
    };
}
  
var mapCanadaToggle =
  document.getElementById(
    "mapCanadaToggle"
  );

var mapCanadaGrid =
  document.getElementById(
    "mapCanadaGrid"
  );

var mapCanadaArrow =
  document.getElementById(
    "mapCanadaArrow"
  );

if(
  mapCanadaToggle &&
  mapCanadaGrid
){

  mapCanadaToggle.onclick = function(){

    var isOpening =
      mapCanadaGrid
        .classList
        .contains("hidden");

    mapCanadaGrid
      .classList
      .toggle("hidden");

    if(mapCanadaArrow){
      mapCanadaArrow.classList.toggle(
        "open",
        isOpening
      );
    }
  };
}
  
  var canadaToggle =
  document.getElementById(
    "canadaToggle"
  );

var canadaProvinceGrid =
  document.getElementById(
    "canadaProvinceGrid"
  );

var canadaArrow =
  document.getElementById(
    "canadaArrow"
  );

if(
  canadaToggle &&
  canadaProvinceGrid
){

  canadaToggle.onclick = function(){

    var isOpening =
      canadaProvinceGrid
        .classList
        .contains("hidden");

    canadaProvinceGrid
      .classList
      .toggle("hidden");

    if(canadaArrow){
      canadaArrow.classList.toggle(
        "open",
        isOpening
      );
    }
  };
}

  
  var closeBadgeBtn = document.getElementById("closeBadgeBtn");
if(closeBadgeBtn) {
  closeBadgeBtn.onclick = function(){
    document.getElementById("badgeOverlay").classList.add("hidden");
  };
}

var badgeDoneBtn = document.getElementById("badgeDoneBtn");
if(badgeDoneBtn) {
  badgeDoneBtn.onclick = function(){
    document.getElementById("badgeOverlay").classList.add("hidden");
  };
}



  document.addEventListener("click", function(e){
  var badgeBtn = e.target.closest(".badge");
  if (!badgeBtn) return;

  var badge = badgeDefs.find(function(b){
    return b.id === badgeBtn.dataset.badgeId;
  });

  if (!badge) return;

  openBadgeDetail(badge);
var confirmPrimaryBtn =
  document.getElementById(
    "confirmPrimaryBtn"
  );

if(confirmPrimaryBtn){

  confirmPrimaryBtn.onclick =
    function(){

      var action =
        confirmAction;

      hideConfirmSheet();

      if(action){
        action();
      }

    };

}

var confirmCancelBtn =
  document.getElementById(
    "confirmCancelBtn"
  );

if(confirmCancelBtn){

  confirmCancelBtn.onclick =
    hideConfirmSheet;

}

var confirmOverlay =
  document.getElementById(
    "confirmOverlay"
  );

if(confirmOverlay){

  confirmOverlay.onclick =
    function(e){

      if(e.target === this){
        hideConfirmSheet();
      }

    };

}
  });



var homeGameOptionsBtn =
  document.getElementById("homeGameOptionsBtn");

var tripOptionsBtn =
  document.getElementById("tripOptionsBtn");

var gameOptionsOverlay =
  document.getElementById("gameOptionsOverlay");

var gameOptionsCloseBtn =
  document.getElementById("gameOptionsCloseBtn");



  
function openGameOptions(){
  if(gameOptionsOverlay){
    gameOptionsOverlay.classList.remove("hidden");
  }
}


  
  
function closeGameOptions(){
  if(gameOptionsOverlay){
    gameOptionsOverlay.classList.add("hidden");
  }
}

if(homeGameOptionsBtn){
  homeGameOptionsBtn.onclick = openGameOptions;
}

if(tripOptionsBtn){
  tripOptionsBtn.onclick = openGameOptions;
}

if(gameOptionsCloseBtn){
  gameOptionsCloseBtn.onclick = closeGameOptions;
}

  var saveTripBtn =
  document.getElementById("saveTripBtn");

if(saveTripBtn){
  saveTripBtn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();

    closeGameOptions();
    saveCurrentTrip();
  };
}


var endTripBtn =
  document.getElementById("endTripBtn");

if(endTripBtn){
  endTripBtn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();

    closeGameOptions();
    endCurrentTrip();
  };
}


var renameTripBtn =
  document.getElementById("renameTripBtn");

if(renameTripBtn){
  renameTripBtn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();

    closeGameOptions();
    openTripNameSheet();
  };
}


var changeModeBtn =
  document.getElementById("changeModeBtn");

if(changeModeBtn){
  changeModeBtn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();

    closeGameOptions();

    var newGameOverlay =
      document.getElementById(
        "newGameOverlay"
      );

    if(newGameOverlay){
      newGameOverlay.dataset.mode =
        "change";
    }

    openNewGameSheet();
  };
}

var addTripPhotoBtn =
  document.getElementById("addTripPhotoBtn");

if(addTripPhotoBtn){
  addTripPhotoBtn.onclick = function(e){

    e.preventDefault();
    e.stopPropagation();

    pendingPhotoStateCode = "TRIP";

    var input =
      document.getElementById(
        "memoryPhotoInput"
      );

    if(input){
      input.value = "";
      input.click();
    }

    closeGameOptions();

  };
}
  

var clearTripBtn =
  document.getElementById("clearTripBtn");

if(clearTripBtn){
  clearTripBtn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();

    openClearTripSheet();
  };
}


var confirmClearTripBtn =
  document.getElementById(
    "confirmClearTripBtn"
  );

if(confirmClearTripBtn){
  confirmClearTripBtn.onclick =
    clearTrip;
}


var cancelClearTripBtn =
  document.getElementById(
    "cancelClearTripBtn"
  );

if(cancelClearTripBtn){
  cancelClearTripBtn.onclick =
    closeClearTripSheet;
}


var clearTripCloseBtn =
  document.getElementById(
    "clearTripCloseBtn"
  );

if(clearTripCloseBtn){
  clearTripCloseBtn.onclick =
    closeClearTripSheet;
}
  
var inviteFriendsBtn = document.getElementById("inviteFriendsBtn");

if(inviteFriendsBtn){
  inviteFriendsBtn.onclick = function(){

    var text =
      "Join my PLATES roadtrip!\n\n" +
      "Friend Code: " + account.friendCode + "\n\n" +
      "https://deanchiungos.github.io/Plates";

    if(navigator.share){

      navigator.share({
        title: "Join my PLATES",
        text: text
      });

    } else {

      navigator.clipboard.writeText(text);
      toast("Invite copied");

    }

  };
}


  var accountCloseBtn = document.getElementById("accountCloseBtn");
if(accountCloseBtn) accountCloseBtn.onclick = closeAccountSheet;

var accountSaveBtn = document.getElementById("accountSaveBtn");
if(accountSaveBtn) accountSaveBtn.onclick = saveAccountFromSheet;


var createAccountBtn = document.getElementById("createAccountBtn");
if(createAccountBtn) {
  createAccountBtn.onclick = createAccount;
}

var copyInviteBtn = document.getElementById("copyInviteBtn");

if(copyInviteBtn) {
  copyInviteBtn.onclick = function() {
    var code = getTripInviteCode();

    navigator.clipboard.writeText(code).then(function() {
      toast("Invite code copied");
    }).catch(function() {
      prompt("Copy this invite code:", code);
    });
  };
}

var shareInviteBtn = document.getElementById("shareInviteBtn");

if (shareInviteBtn) {
  shareInviteBtn.onclick = function () {
    var code = getTripInviteCode();

    var text =
      "Join my PLATES Battle!\n\n" +
      "Battle Code: " + code + "\n\n" +
      "https://deanchiungos.github.io/Plates";

    if (navigator.share) {
      navigator.share({
        title: "Join my PLATES Battle!",
        text: text
      });
    } else {
      navigator.clipboard.writeText(text);
      toast("Battle invite copied");
    }
  };
}

var addFriendOverlay =
  document.getElementById("addFriendOverlay");

var pendingFriend = null;

var friendCodeInput =
  document.getElementById("friendCodeInput");

var findFriendBtn =
  document.getElementById("findFriendBtn");

var friendPreview =
  document.getElementById("friendPreview");

var friendLookupError =
  document.getElementById("friendLookupError");

var confirmAddFriendBtn =
  document.getElementById("confirmAddFriendBtn");

var addFriendCloseBtn =
  document.getElementById("addFriendCloseBtn");

document.querySelectorAll(".addFriendBtn").forEach(function(button){
  button.onclick = function(){

    if(friendCodeInput){
      friendCodeInput.value = "";
    }

    if(friendPreview){
      friendPreview.classList.add("hidden");
    }

    if(friendLookupError){
      friendLookupError.classList.add("hidden");
    }

    pendingFriend = null;

    if(addFriendOverlay){
      addFriendOverlay.classList.remove("hidden");
    }

  };
});

if(addFriendCloseBtn){
  addFriendCloseBtn.onclick = function(){

    if(addFriendOverlay){
      addFriendOverlay.classList.add("hidden");
    }

  };
}

if(findFriendBtn){
  findFriendBtn.onclick = function(){

    var code = "";

    if(friendCodeInput){
      code = friendCodeInput.value
        .trim()
        .toUpperCase();
    }

    if(friendPreview){
      friendPreview.classList.add("hidden");
    }

    if(friendLookupError){
      friendLookupError.classList.add("hidden");
    }

    if(!code || code.indexOf("PLT-") !== 0){

      if(friendLookupError){
        friendLookupError.textContent =
          "Enter a valid friend code";
        friendLookupError.classList.remove("hidden");
      }

      return;
    }

    var alreadyAdded = friends.some(function(friend){
      return friend.id === code;
    });

    if(alreadyAdded){

      if(friendLookupError){
        friendLookupError.textContent =
          "Friend already added";
        friendLookupError.classList.remove("hidden");
      }

      return;
    }

    pendingFriend = {
      id: code,
      name: "PLATES Friend",
      avatar: "😎",
      plate: code.replace("PLT-", ""),
      stateCount: 0,
      points: 0
    };

    var friendPreviewAvatar =
      document.getElementById("friendPreviewAvatar");

    var friendPreviewPlate =
      document.getElementById("friendPreviewPlate");

    var friendPreviewName =
      document.getElementById("friendPreviewName");

    if(friendPreviewAvatar){
      friendPreviewAvatar.textContent =
        pendingFriend.avatar;
    }

    if(friendPreviewPlate){
      friendPreviewPlate.textContent =
        pendingFriend.plate;
    }

    if(friendPreviewName){
      friendPreviewName.textContent =
        pendingFriend.name;
    }

    if(friendPreview){
      friendPreview.classList.remove("hidden");
    }

  };
}

if(confirmAddFriendBtn){
  confirmAddFriendBtn.onclick = function(){

    if(!pendingFriend){
      return;
    }

   friends.push(pendingFriend);
saveFriends();
renderFriends();
renderFriendLeaderboard();
    toast("Friend added");

    pendingFriend = null;

    if(friendPreview){
      friendPreview.classList.add("hidden");
    }

    if(addFriendOverlay){
      addFriendOverlay.classList.add("hidden");
    }

    if(friendCodeInput){
      friendCodeInput.value = "";
    }

  };
}
  
document.querySelectorAll(".state").forEach(function (btn) {
  btn.onclick = function () {
    tapState(btn);
  };
});

document.querySelectorAll("[data-map-code], .svgState").forEach(function (cell) {
  cell.onclick = function () {
    var code =
      cell.dataset.mapCode ||
      cell.dataset.code ||
      cell.getAttribute("data-code");

    if (code) {
      selectMapState(code);
    }
  };
});

var bestStatBtn = document.getElementById("bestStatBtn");

if (bestStatBtn) {
  bestStatBtn.onclick = function () {
    setView("trips");
  };
}

var tripsStatBtn = document.getElementById("tripsStatBtn");
if (tripsStatBtn) {
  tripsStatBtn.onclick = function () {
    setView("trips");
  };
}

var badgesStatBtn = document.getElementById("badgesStatBtn");
if (badgesStatBtn) {
  badgesStatBtn.onclick = function () {
    setView("badges");
  };
}



var modeDropdownBtn = document.getElementById("modeDropdownBtn");


var newGameBtn =
  document.getElementById(
    "newGameBtn"
  );

if(newGameBtn){
  newGameBtn.onclick =
    openNewGameSheet;
}
  
    
  
  var homeGameOptionsBtn = document.getElementById("homeGameOptionsBtn");
var newGameOverlay = document.getElementById("newGameOverlay");
var modeCloseBtn = document.getElementById("modeCloseBtn");
var createGameBtn = document.getElementById("createGameBtn");

if(modeDropdownBtn && newGameOverlay) {
  modeDropdownBtn.onclick = openNewGameSheet;
}

if(newGameBtn && newGameOverlay) {
  newGameBtn.onclick = openNewGameSheet;
}

if(modeCloseBtn) {
  modeCloseBtn.onclick = closeNewGameSheet;
}



if(createGameBtn) {
  createGameBtn.onclick = createGameFromSheet;
}

document.querySelectorAll("[data-game-type]").forEach(function(btn){
  btn.onclick = function() {
    gameType = btn.dataset.gameType;
    syncNewGameSheet();
  };
});

  document.querySelectorAll("[data-mode-choice]").forEach(function(btn){
  btn.onclick = function() {
    mode = btn.dataset.modeChoice;
    scoringMode = mode;
    syncNewGameSheet();
  };
});


  var saveProfileBtn = document.getElementById("saveProfileBtn");
if(saveProfileBtn) saveProfileBtn.onclick = function() {
  document.querySelectorAll(".avatarBtn").forEach(function(btn) {
  btn.onclick = function() {

    profile.avatar = btn.dataset.avatar;

    document.querySelectorAll(".avatarBtn").forEach(function(b){
      b.classList.remove("selected");
    });

    btn.classList.add("selected");
  };
});
  profile.name = document.getElementById("profileName").value;
  profile.email = document.getElementById("profileEmail").value;

  localStorage.setItem(
    "platesProfile",
    JSON.stringify(profile)
  );

  
var profileSavedMsg = document.getElementById("profileSavedMsg");

profileSavedMsg.classList.remove("hidden");

setTimeout(function() {
  profileSavedMsg.classList.add("hidden");
}, 1800);

};

var shareTripBtn = document.getElementById("shareTripBtn");

if(shareTripBtn) {
  shareTripBtn.onclick = shareSummary;
}

var copyShareBtn = document.getElementById("copyShareBtn");

if(copyShareBtn) {
  copyShareBtn.onclick = copyShareText;
}

var celebrationClose = document.getElementById("celebrationClose");

if(celebrationClose) {
  celebrationClose.addEventListener("click", function(e) {
    e.preventDefault();
    e.stopPropagation();

    document
      .getElementById("celebrationOverlay")
      .classList.remove("show");
  });
}


  var resumeGameBtn =
  document.getElementById(
    "resumeGameBtn"
  );



if(resumeGameBtn) {
  resumeGameBtn.onclick =
    function() {

      document
        .getElementById(
          "resumeGameOverlay"
        )
        .classList.add(
          "hidden"
        );

      setView("game");
    };
}

  
var resumeGameCloseBtn =
  document.getElementById(
    "resumeGameCloseBtn"
  );

if(resumeGameCloseBtn) {
  resumeGameCloseBtn.onclick =
    function() {

      document
        .getElementById(
          "resumeGameOverlay"
        )
        .classList.add(
          "hidden"
        );

    };
}



  

var startFreshBtn =
  document.getElementById(
    "startFreshBtn"
  );

if(startFreshBtn) {
  startFreshBtn.onclick =
    function() {

      document
        .getElementById(
          "resumeGameOverlay"
        )
        .classList.add(
          "hidden"
        );

      document
        .getElementById(
          "newGameOverlay"
        )
        .classList.remove(
          "hidden"
        );
    };
}

}

loadProfile();
renderVanityPlate();
attachHandlers();
generateDailyChallenge();
render();
renderFriends();
renderFriendLeaderboard();
showOnboardingIfNeeded();
checkForResumeTrip();
