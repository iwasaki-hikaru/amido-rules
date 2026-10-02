// 動作確認ページ（/check）の判定。
//
// 配信しているルールには、このサイトのホストで次の枠を隠すルールが 1 件ずつ入っている。
//   basic      → .cb-check-basic
//   annoyance  → .cb-check-annoyance
//   privacy    → .cb-check-privacy
// annoyance と privacy は同じ拡張（プラス）に入るが、アプリでは別々にオフにできるので、判定も分ける。
// コンテンツブロッカーが効いていれば、Safari が枠に display: none を当てる。
// ここでは、ページの読み込みが終わってから、枠が隠れているかどうかを見るだけで、外部との通信はしない。
(function () {
  "use strict";

  var checks = [
    { target: "cb-check-basic", result: "result-basic" },
    { target: "cb-check-annoyance", result: "result-annoyance" },
    { target: "cb-check-privacy", result: "result-privacy" }
  ];

  function isHidden(element) {
    return window.getComputedStyle(element).display === "none";
  }

  function show(check) {
    var target = document.getElementById(check.target);
    var result = document.getElementById(check.result);
    if (!target || !result) {
      return;
    }
    var enabled = isHidden(target);
    var text = enabled ? "有効" : "無効";
    // 同じ結果で書き換えると、読み上げが繰り返されるので、変わったときだけ書き換える
    if (result.textContent !== text) {
      result.textContent = text;
    }
    result.className = "result " + (enabled ? "result-on" : "result-off");
  }

  function runChecks() {
    for (var i = 0; i < checks.length; i += 1) {
      show(checks[i]);
    }
  }

  function start() {
    runChecks();
    // ルールの反映が読み込みの完了より遅れる場合に備えて、少しあとにもう一度確かめる
    window.setTimeout(runChecks, 1000);
  }

  function setUpReloadButton() {
    var button = document.getElementById("check-reload");
    if (!button) {
      return;
    }
    // 設定を変えたあとは、ページを読み込み直さないと反映されない
    button.addEventListener("click", function () {
      window.location.reload();
    });
    button.hidden = false;
  }

  setUpReloadButton();
  if (document.readyState === "complete") {
    start();
  } else {
    window.addEventListener("load", start);
  }
  // 戻る操作でキャッシュから表示されたときも、表示を更新する
  window.addEventListener("pageshow", function (event) {
    if (event.persisted) {
      runChecks();
    }
  });
})();
