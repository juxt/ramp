(defproject load-test "0.1.0-SNAPSHOT"
  :description "FIXME: write description"
  :url "http://example.com/FIXME"
  :license {:name "Eclipse Public License"
            :url "http://www.eclipse.org/legal/epl-v10.html"}
  :dependencies [[org.clojure/clojure "1.8.0"]
                 [org.clojure/core.async "0.4.474"]
                 [org.clojure/math.numeric-tower "0.0.4"]
                 [clj-gatling "0.13.0"]
                 ;; [clojider "0.5.0"]
                 ]
  :main ^:skip-aot load-test.core ;; clojider.core 
  :target-path "target/%s"
  :uberjar-explusions [#"scala.*"]
  :profiles {:uberjar {:aot :all}})
