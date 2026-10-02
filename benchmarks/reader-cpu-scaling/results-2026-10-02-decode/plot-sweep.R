args <- commandArgs(TRUE)
x <- read.csv(args[[1]])
svg(args[[2]], width=10, height=4.5, family='sans', bg='white')
par(mfrow=c(1,2), mar=c(4.2,4.5,3,1))
for (kind in c('dta','arrow')) {
  d <- x[x$kind == kind & x$threads != 0, ]
  color <- if (kind == 'dta') '#126B8A' else '#925322'
  plot(d$read_wall, d$read_cpu, type='o', pch=19, col=color, lwd=2,
       xlim=c(0,max(d$read_wall)*1.13), ylim=c(0,max(d$read_cpu)*1.12),
       xlab='Read elapsed time (seconds)', ylab='Total read CPU (seconds)',
       main=if (kind == 'dta') 'DTA' else 'Arrow')
  text(d$read_wall,d$read_cpu,labels=d$threads,pos=4,cex=.85,offset=.5)
  mtext('Labels: requested threads; lower and left is better',side=3,line=.25,cex=.68)
  grid(col='#DDDDDD')
}
invisible(dev.off())
