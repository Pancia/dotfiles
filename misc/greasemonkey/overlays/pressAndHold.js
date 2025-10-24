// pressAndHold jQuery Plugin
// A jQuery plugin that creates a press-and-hold interaction with visual progress indicator

(function($, window, document) {

    var pressAndHold = "pressAndHold",
        defaults = {
            holdTime: 700,
            progressIndicatorRemoveDelay: 300,
            progressIndicatorColor: "#ff0000",
            progressIndicatorOpacity: 0.6,
            allowFastForward: true

        };

    function Plugin(element, options) {
        this.element = element;
        this.settings = $.extend({}, defaults, options);
        this._defaults = defaults;
        this._name = pressAndHold;
        this.init();
    }

    Plugin.prototype = {
        init: function() {
            var _this = this,
                timer,
                decaCounter,
                isActive = false,
                progressIndicatorHTML;


            $(this.element).css({
                display: 'block',
                overflow: 'hidden',
                position: 'relative'
            });

            progressIndicatorHTML = '<div class="holdButtonProgress" style="height: 100%; width: 100%; position: absolute; top: 0; left: -100%; background-color:' + this.settings.progressIndicatorColor + '; opacity:' + this.settings.progressIndicatorOpacity + ';"></div>';

            $(this.element).prepend(progressIndicatorHTML);

            $(this.element).mousedown(function(e) {
                if(e.button == 2) { return; }
                if(isActive) {
                    if(_this.settings.allowFastForward) {
                        decaCounter += 100;
                    }
                    return;
                } else {
                    $(_this.element).trigger('start.pressAndHold');
                    isActive = true;
                    decaCounter = 0;
                    timer = setInterval(function() {
                        decaCounter += 10;
                        $(_this.element).find(".holdButtonProgress").css("left", ((decaCounter / _this.settings.holdTime) * 100 - 100) + "%");
                        if (decaCounter >= _this.settings.holdTime) {
                            isActive = false;
                            _this.exitTimer(timer);
                            $(_this.element).trigger('complete.pressAndHold');
                        }
                    }, 10);
                    $(_this.element).on('mouseleave.pressAndHold', function(event) {
                        isActive = false;
                        _this.exitTimer(timer);
                    });

                }
            });
        },
        exitTimer: function(timer) {
            var _this = this;
            clearTimeout(timer);
            $(this.element).off('mouseleave.pressAndHold');
            setTimeout(function() {
                $(".holdButtonProgress").css("left", "-100%");
                $(_this.element).trigger('end.pressAndHold');
            }, this.settings.progressIndicatorRemoveDelay);
        }
    };

    $.fn[pressAndHold] = function(options) {
        return this.each(function() {
            if (!$.data(this, "plugin_" + pressAndHold)) {
                $.data(this, "plugin_" + pressAndHold, new Plugin(this, options));
            }
        });
    };

})(jQuery, window, document);
