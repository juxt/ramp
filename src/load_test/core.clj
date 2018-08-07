(ns load-test.core
  (:require [clj-gatling.core :as g]
            [clj-time.core :as t]
            [clj-time.format :as f]
            [clojure.core.async :as a]
            [clojure.math.numeric-tower :as math]
            [org.httpkit.client :as http]))

(def test-website "http://website.staging.trustedshops.kermit.cloud/")

(defn get-request
  ([website]
   (get-request website false))
  ([website async?]
   (fn [_]
     (let [{:keys [status]} @(http/get website)]
       (if async?
         (a/go
           (= status 200))
         (= status 200))))))

(defn ramp-up-and-down [progress _]
  (cond ;; stops evaluating at the first match
    (< progress 0.25)
    (* 4 progress)

    (< progress 0.5)
    1

    (< progress 0.75)
    (* 4 (- 0.75 progress))

    :final
    0.1
    ))



(defn gatling
  ([concurrency]
   (gatling concurrency 6))
  ([concurrency seconds]
   (gatling concurrency seconds false))
  ([concurrency seconds async?]
   (let [website test-website
         duration (t/seconds seconds)
         request (get-request website async?)
         start-time (t/now)]
     (println (str "Started at " (f/unparse (f/formatters :hour-minute-second) start-time)))
     (println (str "Ending at ~" (f/unparse (f/formatters :hour-minute-second) (t/plus start-time duration))))
     (let [result 
           (g/run
             {:name "Simulation"
              :scenarios [{:name "GET scenario"
                           :steps [{:name "GET request"
                                    :request request}]}]}
             {:concurrency concurrency
              :concurrency-distribution ramp-up-and-down
              :timeout-in-ms 10000
              :duration duration})]
       (let [end-time (t/now)]
         (println (str "Ended at " (f/unparse (f/formatters :hour-minute-second) end-time)))
         result)))))

(defn -main [& args]
  (gatling "http://website.staging.trustedshops.kermit.cloud/" 2000))
