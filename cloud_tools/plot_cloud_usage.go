package main

import (
	"encoding/csv"
	"fmt"
	"github.com/spf13/cobra"
	"gonum.org/v1/plot"
	"gonum.org/v1/plot/plotter"
	"io"
	"log"
	"os"
	"strconv"
	"time"
)



type ty struct {
	timestamp float64
	value float64
}


func getTimeSeriesFromFile(filepath string, starTime time.Time, endTime time.Time, tag string, tag_index int, timestamp_index int, value_index int) ([]ty, error) {
	//Open file
	f, err := os.Open(filepath)
	if err != nil {
		return nil, err
	}
	defer f.Close()


	csvreader := csv.NewReader(f)

	var tys []ty
	for i := 0;; i = i +1 {
		record, err := csvreader.Read()
		if err == io.EOF {
			break
		} else if err != nil {
			return nil, err
		}
		if record[tag_index] == tag {

			_timestamp, err := strconv.ParseInt(record[timestamp_index], 10, 64)
			if err != nil {
				log.Println("Bad record: %v", err)
				continue
			}
			tm := time.Unix(_timestamp,0)
			if tm.Before(starTime) || tm.After(endTime){
				continue
			}
			_value, err := strconv.ParseFloat(record[value_index], 64)
			if err != nil {
				log.Println("Bad record: %v", err)
				continue
			}

			tys = append(tys, ty{float64(_timestamp), _value})
		}
	}
	return tys, nil

}

func plotData(tys []ty, filepath string, title string, yAxisName string) error {
	p, err := plot.New()
	if err != nil {
		return fmt.Errorf("Could not create plot: %v", err)
	}

	p.Title.Text = title
	xticks := plot.TimeTicks{Format:"15:04:05"}
	p.X.Tick.Marker=xticks
	p.X.Label.Text = "Time"
	p.Y.Label.Text = yAxisName
	ptys := make(plotter.XYs, len(tys))
	for i, ty := range tys {
		ptys[i].X = ty.timestamp
		ptys[i].Y = ty.value
	}

	l, err := plotter.NewLine(ptys)
	if err != nil {
		return fmt.Errorf("Could not create plot line: %v", err)
	}

	p.Add(l)


	//s, err := plotter.NewScatter(ptys)
	//if err != nil {
	//	return fmt.Errorf("Could not create scatter: %v", err)
	//}
	//p.Add(s)
	wt, err := p.WriterTo(1024, 512, "png")
	if err != nil {
		return fmt.Errorf("Could not create writer: %v", err)
	}
	f, err:= os.Create(filepath)
	if err != nil {
		return fmt.Errorf("Could not create %s: %v", filepath, err)
	}
	defer f.Close()
	_, err = wt.WriteTo(f)
	if err != nil {
		return fmt.Errorf("Could not write to %s: %v", filepath, err)
	}

	if err := f.Close(); err != nil {
		return fmt.Errorf("Could not close %s: %v", filepath, err)
	}
	return nil
}
var (
	plotCmd = &cobra.Command{
		Use:   "plot_cloud_usage -flag --flag",
		Short: "Plots cloud usage from csv file",
		Run: func(cmd *cobra.Command, args []string) {
			if csvFilePath == "" {
				log.Fatalf("Please provide a filename to read csv data from via the --csvfilename flag")
			}

			if dataTag == "" {
				log.Fatalf("Please provide a tag value used to indetify the rows to be included")
			}

			if tagIndex == ""{
				log.Fatalf("Please provide a zero based index of the tag location in row")
			}
			tagIndexInt, err := strconv.Atoi(tagIndex)
			if err != nil {
				log.Fatalf("%v", err)
			}

			if valueIndex == "" {
				log.Fatalf("Please provide zero-based positional index of value to be used as y values")
			}
			valueIndexInt, err := strconv.Atoi(valueIndex)
			if err != nil {
				log.Fatalf("%v", err)
			}

			description = dataTag + " " + description

			if outFilePath  == "" {
				log.Fatalf("Please provide a filepath to be used as output. Format will be added as .xxx to resulting filename")
			}
			outFilePath = outFilePath + "."+outFileFormat

			plotLength, err := time.ParseDuration(plotLength)
			if err != nil {
				log.Fatalf("%v", err)
			}

			plotStartDuration, err := time.ParseDuration(plotStart)
			if err != nil {
				log.Fatalf("%v", err)
			}

			plotStartTime:= time.Now().Add(plotStartDuration)


			plotEndTime := plotStartTime.Add(plotLength)
			tys, err := getTimeSeriesFromFile(csvFilePath, plotStartTime, plotEndTime, dataTag, tagIndexInt,
				0, valueIndexInt)
			if err != nil {
				log.Fatalf("Could not read data from file: %v", err)
			}

			plotTitle := plotStartTime.Format("2006-01-02T15:04:0") + " - " +  plotEndTime.Format("2006-01-02T15:04:0")
			if err != nil {
				log.Fatalf("%v", err)
			}
			if len(tys) > 0 {
				err = plotData(tys, outFilePath, plotTitle, description)
				if err != nil {
					log.Fatalf("Could not plot timeseries: %v", err)
				}

			}
		},
	}
)

var csvFilePath, dataTag, tagIndex, valueIndex, description, outFilePath, outFileFormat, plotLength, plotStart string

func main() {
	plotCmd.PersistentFlags().StringVarP(&csvFilePath, "csvfilename", "c", "",
		"full patch to csv file")
	plotCmd.PersistentFlags().StringVarP(&dataTag, "datatag", "d", "",
		"tag value to look for which includes a row into the plot's data")
	plotCmd.PersistentFlags().StringVarP(&tagIndex, "tagindex", "i", "",
		"Zero based positional index of the tag in the row.")
	plotCmd.PersistentFlags().StringVarP(&valueIndex, "valueindex", "v","",
		"Zero based positional index of the value in the row to be used as y values")
	plotCmd.PersistentFlags().StringVarP(&description, "description", "n", "",
		"The name of the y values to be used in the plot legend")
	plotCmd.PersistentFlags().StringVarP(&outFilePath, "outputfile", "o", "",
		"Name of the output file")
	plotCmd.PersistentFlags().StringVarP(&outFileFormat, "format", "f", "png",
		"Graphic format of output file. Currently only png is supported")
	plotCmd.PersistentFlags().StringVarP(&plotLength, "plotlength", "l", "24h",
		"Plot length. For example 24h or 30m Default is 24 hours: 24h")
	plotCmd.PersistentFlags().StringVarP(&plotStart, "plotstart", "s", "-24h",
		"How far back to start plot. example -24h or -30m, etc... Default is 24 hours ago: -24h")

	plotCmd.Execute()

}
