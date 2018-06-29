$(document).ready(function () {
   var minHeight = 0;
   var location = window.location.pathname + window.location.hash;
   $("#tab-container a").each(function(){
      var href = $(this).attr("href");
      if(href==location){
         $(this).parent().addClass("selected");
      }
      minHeight += 60;
   });
   $('#main-container').css('min-height', minHeight+'px');
});
