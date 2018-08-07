(ns load-test.core
  (:require [clj-gatling.core :as g]
            [clj-time.core :as t]
            [clj-time.format :as f]
            [clojure.core.async :as a]
            [clojure.math.numeric-tower :as math]
            [clojure.tools.cli :as cli]
            [org.httpkit.client :as http]))

(def default-website "http://website.staging.trustedshops.kermit.cloud/")

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

(defn half-ramp [progress context]
  ;; (if-not (empty? context) (println context))
  (if (< progress 0.5)
    0.1
    1))

(defn straight-ramp [progress _]
  (print (str progress ";"))
  progress)

(defn gatling
  [& {:keys [website concurrency duration async?]
      :or {website default-website
           concurrency 10000
           duration 12 ;; (* 60 4)
           async? true}}]
  (let [seconds (t/seconds duration)
        request (get-request website async?)
        start-time (t/now)]
    (println (str "Started at " (f/unparse (f/formatters :hour-minute-second) start-time)))
    (println (str "Ending at ~" (f/unparse (f/formatters :hour-minute-second) (t/plus start-time seconds))))
    (let [result 
          (g/run
            {:name "Simulation"
             :scenarios [{:name "GET scenario"
                          :steps [{:name "GET request"
                                   :request request}]}]}
            {:concurrency concurrency
             :concurrency-distribution
             straight-ramp
             ;; half-ramp
             ;; (fn [_ _] 0.5)
             ;; ramp-up-and-down
             :timeout-in-ms 10000
             :duration seconds})]
      (let [end-time (t/now)]
        (println (str "Ended at " (f/unparse (f/formatters :hour-minute-second) end-time)))
        result))))

(def cli-options
  [["-c" "--concurrency CONCURRENCY" "Concurrency"
    :default 10000
    :parse-fn #(Integer/parseInt %)]
   ["-d" "--duration DURATION" "Duration"
    :default (* 60 3)
    :parse-fn #(Integer/parseInt %)]
   ["-a" "--asynch" "Asynch?"
    :default true
    :parse-fn #(Boolean/parseBoolean %)]
   ["-h" "--help"]])

(defn -main [& args]
  (let [opts (cli/parse-opts args cli-options)]
    (gatling (:options opts))))
